"""
Cairo Test System - Runtime and Type Integration

This module handles the execution of Cairo programs and provides the core integration
with the type system for testing. It enables running tests with inputs passed as pure Python by automatically
handling type conversion between Python and Cairo.

The runner works with args_gen.py and serde.py for automatic type conversion.
"""

import json
import logging
import marshal
from hashlib import md5
from pathlib import Path
from time import time_ns
from typing import Tuple

import polars as pl
import pytest
import starkware.cairo.lang.instances as LAYOUTS
from cairo_addons.vm import CairoRunner
from cairo_addons.vm import Program as RustProgram
from cairo_addons.vm import RunResources
from starkware.cairo.common.dict import DictManager
from starkware.cairo.lang.builtins.all_builtins import ALL_BUILTINS
from starkware.cairo.lang.compiler.ast.cairo_types import CairoType, TypeStruct
from starkware.cairo.lang.compiler.program import Program
from starkware.cairo.lang.compiler.scoped_name import ScopedName
from starkware.cairo.lang.vm.memory_segments import FIRST_MEMORY_ADDR as PROGRAM_BASE

from tests.utils.args_gen import gen_arg as gen_arg_builder
from tests.utils.args_gen import to_python_type
from tests.utils.helpers import flatten
from tests.utils.reporting import profile_from_tracer_data
from tests.utils.serde import NO_ERROR_FLAG, Serde

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger()


def resolve_main_path(main_path: Tuple[str, ...]):
    """
    Resolve Cairo type paths for proper type system integration.

    It ensures types defined in __main__ (when the test file is the main file)
    are properly mapped to their actual module paths for serialization/deserialization.
    """

    def _factory(cairo_type: CairoType):
        if isinstance(cairo_type, TypeStruct):
            full_path = cairo_type.scope.path
            if "__main__" in full_path:
                full_path = main_path + full_path[full_path.index("__main__") + 1 :]
                cairo_type.scope = ScopedName(full_path)
        return cairo_type

    return _factory


@pytest.fixture(scope="module")
def cairo_file(request):
    return request.session.cairo_files[request.node.fspath]


@pytest.fixture(scope="module")
def cairo_program(request) -> Program:
    return request.session.cairo_programs[request.node.fspath]


@pytest.fixture(scope="module")
def main_path(request):
    return request.session.main_paths[request.node.fspath]


@pytest.fixture(scope="module")
def cairo_run(request, cairo_program: Program, cairo_file, main_path):
    """
    Run the cairo program corresponding to the python test file at a given entrypoint with given program inputs as kwargs.
    Returns the output of the cairo program put in the output memory segment.

    When --profile-cairo is passed, the cairo program is run with the tracer enabled and the resulting trace is dumped.

    Logic is mainly taken from starkware.cairo.lang.vm.cairo_run with minor updates, mainly builtins discovery from implicit args.

    Type conversion between Python and Cairo is handled by:
    - gen_arg: Converts Python arguments to Cairo memory layout when preparing runner inputs
    - serde: Converts Cairo memory data to Python types by reading into the segments, used to return python types.

    Returns:
        The function's return value, converted back to Python types
    """

    def _factory(entrypoint, *args, **kwargs):
        implicit_args = cairo_program.identifiers.get_by_full_name(
            ScopedName(path=("__main__", entrypoint, "ImplicitArgs"))
        ).members

        # Split implicit args into builtins and other implicit args
        _builtins = [
            k
            for k in implicit_args.keys()
            if any(builtin in k.replace("_ptr", "") for builtin in ALL_BUILTINS)
        ]
        # Set program builtins based on the implicit args
        cairo_program.builtins = [
            builtin
            for builtin in ALL_BUILTINS
            if builtin in [arg.replace("_ptr", "") for arg in _builtins]
        ]

        # Get actual args from implicit and explicit args
        _implicit_args = {
            k: {
                "python_type": to_python_type(
                    resolve_main_path(main_path)(v.cairo_type)
                ),
                "cairo_type": v.cairo_type,
            }
            for k, v in implicit_args.items()
            if not any(builtin in k.replace("_ptr", "") for builtin in ALL_BUILTINS)
        }

        _args = {
            k: {
                "python_type": to_python_type(
                    resolve_main_path(main_path)(v.cairo_type)
                ),
                "cairo_type": v.cairo_type,
            }
            for k, v in cairo_program.identifiers.get_by_full_name(
                ScopedName(path=("__main__", entrypoint, "Args"))
            ).members.items()
        }

        explicit_return_data = cairo_program.identifiers.get_by_full_name(
            ScopedName(path=("__main__", entrypoint, "Return"))
        ).cairo_type
        return_data_types = [arg["cairo_type"] for arg in _implicit_args.values()] + (
            [explicit_return_data]
            if not (
                hasattr(explicit_return_data, "members")
                and len(explicit_return_data.members) == 0
            )
            else []
        )

        # Create runner
        runner = CairoRunner(
            program=RustProgram.from_bytes(
                json.dumps(cairo_program.Schema().dump(cairo_program)).encode()
            ),
            layout=getattr(LAYOUTS, request.config.getoption("layout")).layout_name,
            proof_mode=False,
            allow_missing_builtins=False,
        )

        # Fill runner's memory for args
        serde = Serde(runner.segments, cairo_program, cairo_file)
        dict_manager = DictManager()
        gen_arg = gen_arg_builder(dict_manager, runner.segments)
        stack = []
        for i, (arg_name, python_type) in enumerate(
            [(k, v["python_type"]) for k, v in {**_implicit_args, **_args}.items()]
        ):
            arg_value = kwargs[arg_name] if arg_name in kwargs else args[i]
            stack.append(gen_arg(python_type, arg_value))

        # Initialize runner
        end = runner.initialize(
            builtins=cairo_program.builtins,
            entrypoint=cairo_program.get_label(entrypoint),
            stack=stack,
        )

        # Run
        # hint_locals={
        #     "program_input": kwargs,
        #     "__dict_manager": dict_manager,
        #     "gen_arg": gen_arg,
        #     "serde": serde,
        #     "oracle": oracle(cairo_program, serde, main_path, gen_arg),
        #     "to_cairo_type": partial(to_cairo_type, cairo_program),
        # }
        # static_locals={
        #     "debug_info": debug_info(cairo_program),
        #     "get_op": get_op,
        #     "logger": logger,
        # }
        runner.run_until_pc(end, RunResources())
        cumulative_retdata_offsets = serde.get_offsets(return_data_types)
        first_return_data_offset = (
            cumulative_retdata_offsets[0] if cumulative_retdata_offsets else 0
        )
        runner.verify_and_relocate(offset=first_return_data_offset)

        # Create a unique output stem for the given test by using the test file name, the entrypoint and the kwargs
        displayed_args = ""
        if kwargs:
            try:
                displayed_args = json.dumps(kwargs)
            except TypeError as e:
                logger.info(f"Failed to serialize kwargs: {e}")
        output_stem = str(
            request.node.path.parent
            / f"{request.node.path.stem}_{entrypoint}_{displayed_args}"
        )
        # File names cannot be longer than 255 characters on Unix so we slice the base stem and happen a unique suffix
        # Timestamp is used to avoid collisions when running the same test multiple times and to allow sorting by time
        output_stem = Path(
            f"{output_stem[:160]}_{int(time_ns())}_{md5(output_stem.encode()).digest().hex()[:8]}"
        )
        if request.config.getoption("profile_cairo"):
            trace = pl.DataFrame(
                [{"pc": x.pc, "ap": x.ap, "fp": x.fp} for x in runner.relocated_trace]
            )
            stats, prof_dict = profile_from_tracer_data(
                program=cairo_program, trace=trace, program_base=PROGRAM_BASE
            )
            stats = stats[
                "scope",
                "primitive_call",
                "total_call",
                "total_cost",
                "cumulative_cost",
            ].sort("cumulative_cost", descending=True)
            logger.info(stats)
            stats.write_csv(output_stem.with_suffix(".csv"))
            marshal.dump(prof_dict, open(output_stem.with_suffix(".prof"), "wb"))

        final_output = None
        unfiltered_output = [
            serde.serialize(return_data_type, runner.ap, offset)
            for offset, return_data_type in zip(
                cumulative_retdata_offsets, return_data_types
            )
        ]
        function_output = [x for x in unfiltered_output if x is not NO_ERROR_FLAG]
        exceptions = [
            val
            for val in flatten(function_output)
            if hasattr(val, "__class__") and issubclass(val.__class__, Exception)
        ]
        if exceptions:
            raise exceptions[0]

        if final_output is not None:
            if len(function_output) > 0:
                final_output = (final_output, *function_output)
        else:
            final_output = function_output

        return final_output[0] if len(final_output) == 1 else final_output

    return _factory

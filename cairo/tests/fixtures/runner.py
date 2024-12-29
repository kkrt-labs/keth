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
import math
from functools import partial
from hashlib import md5
from pathlib import Path
from time import time_ns
from typing import Tuple

import pytest
import starkware.cairo.lang.instances as LAYOUTS
from starkware.cairo.common.dict import DictManager
from starkware.cairo.lang.builtins.all_builtins import ALL_BUILTINS
from starkware.cairo.lang.compiler.ast.cairo_types import CairoType, TypeStruct
from starkware.cairo.lang.compiler.scoped_name import ScopedName
from starkware.cairo.lang.tracer.tracer_data import TracerData
from starkware.cairo.lang.vm.cairo_run import (
    write_air_public_input,
    write_binary_memory,
    write_binary_trace,
)
from starkware.cairo.lang.vm.cairo_runner import CairoRunner
from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import FIRST_MEMORY_ADDR as PROGRAM_BASE
from starkware.cairo.lang.vm.security import verify_secure_runner
from starkware.cairo.lang.vm.utils import RunResources

from tests.utils.args_gen import gen_arg as gen_arg_builder
from tests.utils.args_gen import to_cairo_type, to_python_type
from tests.utils.hints import debug_info, get_op, oracle
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
def cairo_program(request):
    return request.session.cairo_programs[request.node.fspath]


@pytest.fixture(scope="module")
def main_path(request):
    return request.session.main_paths[request.node.fspath]


@pytest.fixture(scope="module")
def cairo_run(request, cairo_program, cairo_file, main_path):
    """
    Run the cairo program corresponding to the python test file at a given entrypoint with given program inputs as kwargs.
    Returns the output of the cairo program put in the output memory segment.

    When --profile-cairo is passed, the cairo program is run with the tracer enabled and the resulting trace is dumped.

    Logic is mainly taken from starkware.cairo.lang.vm.cairo_run with minor updates, mainly builtins discovery from implicit args and proof mode enabling by appending jmp rel 0 to the compiled program.

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
        return_data_types = [
            *(arg["cairo_type"] for arg in _implicit_args.values()),
            # Filter for the empty tuple return type
            *(
                [explicit_return_data]
                if not (
                    hasattr(explicit_return_data, "members")
                    and len(explicit_return_data.members) == 0
                )
                else []
            ),
        ]

        # Fix builtins runner based on the implicit args since the compiler doesn't find them
        cairo_program.builtins = [
            builtin
            for builtin in ALL_BUILTINS
            if builtin in [arg.replace("_ptr", "") for arg in _builtins]
        ]
        # Add a jmp rel 0 instruction to be able to loop in proof mode and avoid the proof-mode at compile time
        cairo_program.data = cairo_program.data + [0x10780017FFF7FFF, 0]
        memory = MemoryDict()
        runner = CairoRunner(
            program=cairo_program,
            layout=getattr(LAYOUTS, request.config.getoption("layout")),
            memory=memory,
            proof_mode=request.config.getoption("proof_mode"),
            allow_missing_builtins=False,
        )
        serde = Serde(runner.segments, cairo_program, cairo_file)
        dict_manager = DictManager()
        gen_arg = gen_arg_builder(dict_manager, runner.segments)

        runner.program_base = runner.segments.add()
        runner.execution_base = runner.segments.add()
        for builtin_runner in runner.builtin_runners.values():
            builtin_runner.initialize_segments(runner)

        add_output = False
        stack = []

        # Handle builtins
        for builtin_arg in _builtins:
            builtin_runner = runner.builtin_runners.get(
                builtin_arg.replace("_ptr", "_builtin")
            )
            if builtin_runner is None:
                raise ValueError(f"Builtin runner {builtin_arg} not found")
            stack.extend(builtin_runner.initial_stack())
            add_output = "output" in builtin_arg
            if add_output:
                output_ptr = stack[-1]

        # Handle other args, (implicit, explicit)
        for i, (arg_name, python_type) in enumerate(
            [(k, v["python_type"]) for k, v in {**_implicit_args, **_args}.items()]
        ):
            if arg_name == "output_ptr":
                add_output = True
                output_ptr = runner.segments.add()
                stack.append(output_ptr)
            else:
                arg_value = kwargs[arg_name] if arg_name in kwargs else args[i]
                stack.append(gen_arg(python_type, arg_value))

        return_fp = runner.execution_base + 2
        # Return to the jmp rel 0 instruction added previously
        end = runner.program_base + len(runner.program.data) - 2
        # Proof mode expects the program to start with __start__ and call main
        # Adding [return_fp, end] before and after the stack makes this work both in proof mode and normal mode
        stack = [return_fp, end] + stack + [return_fp, end]
        runner.execution_public_memory = list(range(len(stack)))

        runner.initial_pc = runner.program_base + cairo_program.get_label(entrypoint)
        runner.load_data(runner.program_base, runner.program.data)
        runner.load_data(runner.execution_base, stack)
        runner.initial_fp = runner.initial_ap = runner.execution_base + len(stack)
        runner.initialize_zero_segment()
        runner.initialize_vm(
            hint_locals={
                "program_input": kwargs,
                "__dict_manager": dict_manager,
                "gen_arg": gen_arg,
                "serde": serde,
                "oracle": oracle(cairo_program, serde, main_path, gen_arg),
                "to_cairo_type": partial(to_cairo_type, cairo_program),
            },
            static_locals={
                "debug_info": debug_info(cairo_program),
                "get_op": get_op,
                "logger": logger,
            },
        )
        run_resources = RunResources(n_steps=500_000_000)
        try:
            runner.run_until_pc(end, run_resources)
        except Exception as e:
            raise Exception(str(e)) from e

        runner.end_run(disable_trace_padding=False)
        cumulative_retdata_offsets = serde.get_offsets(return_data_types)
        first_return_data_offset = (
            cumulative_retdata_offsets[0] if cumulative_retdata_offsets else 0
        )
        pointer = runner.vm.run_context.ap - first_return_data_offset
        for arg in _builtins[::-1]:
            builtin_runner = runner.builtin_runners.get(arg.replace("_ptr", "_builtin"))
            if builtin_runner is not None:
                pointer = builtin_runner.final_stack(runner, pointer)
            else:
                pointer -= 1

        if request.config.getoption("proof_mode"):
            runner.execution_public_memory += list(
                range(
                    pointer.offset,
                    runner.vm.run_context.ap.offset - first_return_data_offset,
                )
            )
            runner.finalize_segments()

        verify_secure_runner(runner)
        runner.relocate()

        logger.info(
            f"\nExecution resources: {json.dumps(runner.get_execution_resources().to_dict(), indent=4)}"
        )

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
            tracer_data = TracerData(
                program=cairo_program,
                memory=runner.relocated_memory,
                trace=runner.relocated_trace,
                debug_info=runner.get_relocated_debug_info(),
                program_base=PROGRAM_BASE,
            )
            stats, prof_dict = profile_from_tracer_data(tracer_data)
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

        if request.config.getoption("proof_mode"):
            with open(output_stem.with_suffix(".trace"), "wb") as fp:
                write_binary_trace(fp, runner.relocated_trace)

            with open(output_stem.with_suffix(".memory"), "wb") as fp:
                write_binary_memory(
                    fp,
                    runner.relocated_memory,
                    math.ceil(cairo_program.prime.bit_length() / 8),
                )

            rc_min, rc_max = runner.get_perm_range_check_limits()
            with open(output_stem.with_suffix(".air_public_input.json"), "w") as fp:
                write_air_public_input(
                    layout=request.config.getoption("layout"),
                    public_input_file=fp,
                    memory=runner.relocated_memory,
                    public_memory_addresses=runner.segments.get_public_memory_addresses(
                        segment_offsets=runner.get_segment_offsets()
                    ),
                    memory_segment_addresses=runner.get_memory_segment_addresses(),
                    trace=runner.relocated_trace,
                    rc_min=rc_min,
                    rc_max=rc_max,
                )
            with open(output_stem.with_suffix(".air_private_input.json"), "w") as fp:
                json.dump(
                    {
                        "trace_path": str(output_stem.with_suffix(".trace").absolute()),
                        "memory_path": str(
                            output_stem.with_suffix(".memory").absolute()
                        ),
                        **runner.get_air_private_input(),
                    },
                    fp,
                    indent=4,
                )

        final_output = None
        if add_output:
            final_output = serde.serialize_list(output_ptr)

        cumulative_retdata_offsets = serde.get_offsets(return_data_types)
        unfiltered_output = [
            serde.serialize(return_data_type, runner.vm.run_context.ap, offset)
            for offset, return_data_type in zip(
                cumulative_retdata_offsets, return_data_types
            )
        ]
        function_output = [x for x in unfiltered_output if x is not NO_ERROR_FLAG]

        if final_output is not None:
            if len(function_output) > 0:
                final_output = (final_output, *function_output)
        else:
            final_output = function_output

        return final_output[0] if len(final_output) == 1 else final_output

    return _factory

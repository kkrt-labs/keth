import json
import logging
import math
from functools import partial
from hashlib import md5
from pathlib import Path
from time import time_ns
from typing import Tuple

import pytest
import starkware.cairo.lang.instances as LAYOUTS
from hypothesis import settings
from starkware.cairo.common.dict import DictManager
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
from starkware.cairo.lang.vm.utils import RunResources

from tests.utils.args_gen import gen_arg as gen_arg_builder
from tests.utils.args_gen import to_cairo_type, to_python_type
from tests.utils.caching import program_hash, testfile_hash
from tests.utils.coverage import VmWithCoverage
from tests.utils.hints import debug_info, get_op, oracle
from tests.utils.reporting import profile_from_tracer_data
from tests.utils.serde import Serde

logger = logging.getLogger()


def resolve_main_path(main_path: Tuple[str, ...]):

    def _factory(cairo_type: CairoType):
        if isinstance(cairo_type, TypeStruct):
            full_path = cairo_type.scope.path
            if "__main__" in full_path:
                full_path = main_path + full_path[full_path.index("__main__") + 1 :]
                cairo_type.scope = ScopedName(full_path)
        return cairo_type

    return _factory


@pytest.fixture(scope="module")
def cairo_run(request, worker_id, cairo_program, cairo_file, main_path):
    """
    Run the cairo program corresponding to the python test file at a given entrypoint with given program inputs as kwargs.
    Returns the output of the cairo program put in the output memory segment.

    When --profile-cairo is passed, the cairo program is run with the tracer enabled and the resulting trace is dumped.

    Logic is mainly taken from starkware.cairo.lang.vm.cairo_run with minor updates like the addition of the output segment.
    """

    cached_tests_file = "cairo_run/cached_tests.json"
    cached_test_key = f"{str(cairo_file)}::{worker_id}"
    current_hash = (
        program_hash(cairo_program) + testfile_hash(request.node.fspath)
    ).hex()
    all_cached_tests = request.config.cache.get(cached_tests_file, {})
    request.config.cache.set(
        cached_tests_file, {**all_cached_tests, cached_test_key: current_hash}
    )

    if (
        all_cached_tests.get(cached_test_key) == current_hash
        and request.config.getoption("skip_cached_tests")
        and settings()._current_profile != "nightly"
    ):
        pytest.skip(f"Skipping {request.node.name}: no change in program nor test file")

    def _factory(entrypoint, *args, **kwargs):
        implicit_args = list(
            cairo_program.identifiers.get_by_full_name(
                ScopedName(path=("__main__", entrypoint, "ImplicitArgs"))
            ).members.keys()
        )
        _args = {
            k: to_python_type(resolve_main_path(main_path)(v.cairo_type))
            for k, v in cairo_program.identifiers.get_by_full_name(
                ScopedName(path=("__main__", entrypoint, "Args"))
            ).members.items()
        }
        return_data = cairo_program.identifiers.get_by_full_name(
            ScopedName(path=("__main__", entrypoint, "Return"))
        )
        # Fix builtins runner based on the implicit args since the compiler doesn't find them
        cairo_program.builtins = [
            builtin
            # This list is extracted from the builtin runners
            # Builtins have to be declared in this order
            for builtin in [
                "output",
                "pedersen",
                "range_check",
                "ecdsa",
                "bitwise",
                "ec_op",
                "keccak",
                "poseidon",
                "range_check96",
                "add_mod",
                "mul_mod",
            ]
            if builtin in {arg.replace("_ptr", "") for arg in implicit_args}
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
        for arg in implicit_args:
            builtin_runner = runner.builtin_runners.get(arg.replace("_ptr", "_builtin"))
            if builtin_runner is not None:
                stack.extend(builtin_runner.initial_stack())
                add_output = "output" in arg
                if add_output:
                    output_ptr = stack[-1]

        for i, (arg_name, python_type) in enumerate(_args.items()):
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
            },
            vm_class=VmWithCoverage,
        )
        run_resources = RunResources(n_steps=64_000_000)
        try:
            runner.run_until_pc(end, run_resources)
        except Exception as e:
            raise Exception(str(e)) from e

        runner.end_run(disable_trace_padding=False)
        if request.config.getoption("proof_mode"):
            return_data_offset = serde.get_offset(return_data.cairo_type)
            pointer = runner.vm.run_context.ap - return_data_offset
            for arg in implicit_args[::-1]:
                builtin_runner = runner.builtin_runners.get(
                    arg.replace("_ptr", "_builtin")
                )
                if builtin_runner is not None:
                    builtin_runner.final_stack(runner, pointer)
                pointer -= 1

            runner.execution_public_memory += list(
                range(
                    pointer.offset, runner.vm.run_context.ap.offset - return_data_offset
                )
            )
            runner.finalize_segments()

        runner.relocate()

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
            data = profile_from_tracer_data(tracer_data)

            with open(output_stem.with_suffix(".pb.gz"), "wb") as fp:
                fp.write(data)

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
        function_output = serde.serialize(
            return_data.cairo_type, runner.vm.run_context.ap
        )
        if final_output is not None:
            function_output = (
                function_output
                if isinstance(function_output, list)
                else [function_output]
            )
            if len(function_output) > 0:
                final_output = (final_output, *function_output)
        else:
            final_output = function_output

        return final_output

    return _factory

import logging
import os

os.environ["PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION"] = "python"

import json
import math
import shutil
from hashlib import md5
from pathlib import Path
from time import perf_counter, time_ns

import pytest
from dotenv import load_dotenv
from hypothesis import Phase, Verbosity, settings
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME
from starkware.cairo.lang.compiler.cairo_compile import compile_cairo, get_module_reader
from starkware.cairo.lang.compiler.preprocessor.default_pass_manager import (
    default_pass_manager,
)
from starkware.cairo.lang.compiler.scoped_name import ScopedName
from starkware.cairo.lang.instances import LAYOUTS
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

from tests.utils.constants import Opcodes
from tests.utils.coverage import VmWithCoverage, report_runs
from tests.utils.hints import implement_hints
from tests.utils.reporting import dump_coverage, profile_from_tracer_data
from tests.utils.serde import Serde

load_dotenv()
logger = logging.getLogger()


def pytest_addoption(parser):
    parser.addoption(
        "--profile-cairo",
        action="store_true",
        default=False,
        help="compute and dump TracerData for the VM runner: True or False",
    )
    parser.addoption(
        "--proof-mode",
        action="store_true",
        default=False,
        help="run the CairoRunner in proof mode: True or False",
    )
    parser.addoption(
        "--layout",
        choices=list(LAYOUTS.keys()),
        default="starknet_with_keccak",
        help="The layout of the Cairo AIR.",
    )
    parser.addoption(
        "--seed",
        action="store",
        default=None,
        type=int,
        help="The seed to set random with.",
    )


@pytest.fixture(autouse=True, scope="session")
def seed(request):
    if request.config.getoption("seed") is not None:
        import random

        logger.info(f"Setting seed to {request.config.getoption('seed')}")

        random.seed(request.config.getoption("seed"))


def cairo_compile(path):
    module_reader = get_module_reader(cairo_path=[str(Path(__file__).parents[1])])

    pass_manager = default_pass_manager(
        prime=DEFAULT_PRIME, read_module=module_reader.read
    )

    return compile_cairo(
        Path(path).read_text(),
        pass_manager=pass_manager,
        debug_info=True,
    )


@pytest.fixture(scope="module")
def cairo_program(request) -> list:
    cairo_file = Path(request.node.fspath).with_suffix(".cairo")
    if not cairo_file.exists():
        raise ValueError(f"Missing cairo file: {cairo_file}")

    start = perf_counter()
    program = cairo_compile(cairo_file)
    program.hints = implement_hints(program)
    stop = perf_counter()
    logger.info(f"{cairo_file} compiled in {stop - start:.2f}s")
    return program


@pytest.fixture(scope="module")
def cairo_run(request, cairo_program) -> list:
    """
    Run the cairo program corresponding to the python test file at a given entrypoint with given program inputs as kwargs.
    Returns the output of the cairo program put in the output memory segment.

    When --profile-cairo is passed, the cairo program is run with the tracer enabled and the resulting trace is dumped.

    Logic is mainly taken from starkware.cairo.lang.vm.cairo_run with minor updates like the addition of the output segment.
    """

    def _factory(entrypoint, **kwargs) -> list:
        implicit_args = list(
            cairo_program.identifiers.get_by_full_name(
                ScopedName(path=["__main__", entrypoint, "ImplicitArgs"])
            ).members.keys()
        )
        args = list(
            cairo_program.identifiers.get_by_full_name(
                ScopedName(path=["__main__", entrypoint, "Args"])
            ).members.keys()
        )
        return_data = cairo_program.identifiers.get_by_full_name(
            ScopedName(path=["__main__", entrypoint, "Return"])
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

        memory = MemoryDict()
        runner = CairoRunner(
            program=cairo_program,
            layout=request.config.getoption("layout"),
            memory=memory,
            proof_mode=request.config.getoption("proof_mode"),
            allow_missing_builtins=False,
        )
        serde = Serde(runner)

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
                continue

        add_output = add_output or "output_ptr" in args
        if add_output:
            output_ptr = runner.segments.add()
            stack.append(output_ptr)

        return_fp = runner.execution_base + 2
        end = runner.segments.add()
        # Add a jmp rel 0 instruction to be able to loop in proof mode
        runner.memory[end] = 0x10780017FFF7FFF
        runner.memory[end + 1] = 0
        # Proof mode expects the program to start with __start__ and call main
        # Adding [return_fp, end] before and after the stack makes this work both in proof mode and normal mode
        stack = [return_fp, end] + stack + [return_fp, end]
        runner.execution_public_memory = list(range(len(stack)))

        runner.initialize_state(
            entrypoint=cairo_program.identifiers.get_by_full_name(
                ScopedName(path=["__main__", entrypoint])
            ).pc,
            stack=stack,
        )
        runner.initial_fp = runner.initial_ap = runner.execution_base + len(stack)

        runner.initialize_vm(
            hint_locals={"program_input": kwargs},
            static_locals={
                "serde": serde,
                "Opcodes": Opcodes,
            },
            vm_class=VmWithCoverage,
        )
        run_resources = RunResources(n_steps=10_000_000)
        try:
            runner.run_until_pc(end, run_resources)
        except Exception as e:
            raise Exception(str(e)) from e

        runner.original_steps = runner.vm.current_step
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
                    pointer.offset,
                    runner.vm.run_context.ap.offset - return_data_offset,
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
        function_output = serde.serialize(return_data.cairo_type)
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


@pytest.fixture(scope="session", autouse=True)
def coverage(worker_id):

    output_dir = Path("coverage")
    shutil.rmtree(output_dir, ignore_errors=True)

    yield

    output_dir.mkdir(exist_ok=True, parents=True)
    files = report_runs(excluded_file={"site-packages", "tests"})

    if worker_id == "master":
        dump_coverage(output_dir, files)
    else:
        dump_coverage(output_dir / worker_id, files)


settings.register_profile(
    "nightly",
    deadline=None,
    max_examples=1500,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
)
settings.register_profile(
    "ci",
    deadline=None,
    max_examples=100,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
)
settings.register_profile(
    "dev",
    deadline=None,
    max_examples=10,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
)
settings.register_profile(
    "debug",
    max_examples=10,
    verbosity=Verbosity.verbose,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
)
settings.load_profile(os.getenv("HYPOTHESIS_PROFILE", "default"))
logger.info(f"Using Hypothesis profile: {os.getenv('HYPOTHESIS_PROFILE', 'default')}")

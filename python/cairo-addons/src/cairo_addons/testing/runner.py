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
from typing import Callable, List, Optional, Tuple, Type

import polars as pl
import starkware.cairo.lang.instances as LAYOUTS
from pytest import FixtureRequest
from starkware.cairo.common.dict import DictManager
from starkware.cairo.lang.builtins.all_builtins import ALL_BUILTINS
from starkware.cairo.lang.compiler.ast.cairo_types import (
    CairoType,
    TypeFelt,
    TypePointer,
    TypeStruct,
    TypeTuple,
)
from starkware.cairo.lang.compiler.identifier_definition import (
    StructDefinition,
    TypeDefinition,
)
from starkware.cairo.lang.compiler.program import Program
from starkware.cairo.lang.compiler.scoped_name import ScopedName
from starkware.cairo.lang.vm.cairo_run import (
    write_air_public_input,
    write_binary_memory,
    write_binary_trace,
)
from starkware.cairo.lang.vm.cairo_runner import CairoRunner
from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import FIRST_MEMORY_ADDR as PROGRAM_BASE
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.relocatable import RelocatableValue
from starkware.cairo.lang.vm.security import verify_secure_runner
from starkware.cairo.lang.vm.utils import RunResources
from starkware.cairo.lang.vm.vm import VirtualMachine

from cairo_addons.profiler import profile_from_trace
from cairo_addons.testing.errors import map_to_python_exception
from cairo_addons.testing.hints import debug_info, oracle
from cairo_addons.testing.serde import Serde, SerdeProtocol
from cairo_addons.testing.utils import flatten
from cairo_addons.vm import CairoRunner as RustCairoRunner
from cairo_addons.vm import Program as RustProgram
from cairo_addons.vm import RunResources as RustRunResources

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger()


def to_python_type(cairo_type: CairoType):
    if isinstance(cairo_type, TypeFelt):
        return int

    if isinstance(cairo_type, TypeTuple):
        return tuple

    if isinstance(cairo_type, TypePointer):
        return RelocatableValue


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


def build_entrypoint(
    cairo_program: Program,
    entrypoint: str,
    main_path: Tuple[str, ...],
    to_python_type: Callable = to_python_type,
):
    implicit_args = cairo_program.get_identifier(
        f"{entrypoint}.ImplicitArgs", StructDefinition
    ).members

    # Split implicit args into builtins and other implicit args
    _builtins = [
        k
        for k in implicit_args.keys()
        if any(builtin in k.replace("_ptr", "") for builtin in ALL_BUILTINS)
    ]

    _implicit_args = {
        k: {
            "python_type": to_python_type(resolve_main_path(main_path)(v.cairo_type)),
            "cairo_type": v.cairo_type,
        }
        for k, v in implicit_args.items()
        if not any(builtin in k.replace("_ptr", "") for builtin in ALL_BUILTINS)
    }

    entrypoint_args = cairo_program.get_identifier(
        f"{entrypoint}.Args", StructDefinition
    ).members

    _args = {
        k: {
            "python_type": to_python_type(resolve_main_path(main_path)(v.cairo_type)),
            "cairo_type": v.cairo_type,
        }
        for k, v in entrypoint_args.items()
    }

    explicit_return_data = cairo_program.get_identifier(
        f"{entrypoint}.Return", TypeDefinition
    ).cairo_type

    return_data_types = [
        *(arg["cairo_type"] for arg in _implicit_args.values()),
        # Filter for the empty tuple return type
        *(
            [explicit_return_data]
            if not (
                isinstance(explicit_return_data, TypeTuple)
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

    return _builtins, _implicit_args, _args, return_data_types


def run_python_vm(
    cairo_programs: List[Program],
    cairo_files: List[Path],
    main_paths: List[Tuple[str, ...]],
    request: FixtureRequest,
    gen_arg_builder: Optional[
        Callable[[DictManager, MemorySegmentManager], Callable]
    ] = None,
    to_python_type: Callable = to_python_type,
    to_cairo_type: Optional[Callable] = None,
    serde_cls: Type[SerdeProtocol] = Serde,
    hint_locals: Optional[dict] = None,
    static_locals: Optional[dict] = None,
    coverage: Optional[Callable[[pl.DataFrame, int], pl.DataFrame]] = None,
):
    """Helper function containing Python VM implementation"""
    from cairo_addons.hints.injected import prepare_context

    def _run(entrypoint, *args, **kwargs):
        cairo_program = cairo_programs[0]
        cairo_file = cairo_files[0]
        main_path = main_paths[0]
        try:
            cairo_program.get_label(entrypoint)
        except Exception:
            # Entrypoint not found - try test program
            cairo_program = cairo_programs[1]
            cairo_file = cairo_files[1]
            main_path = main_paths[1]

        _builtins, _implicit_args, _args, return_data_types = build_entrypoint(
            cairo_program, entrypoint, main_path, to_python_type
        )

        # Add a jmp rel 0 instruction to be able to loop in proof mode and avoid the proof-mode at compile time
        proof_mode = request.config.getoption("proof_mode")
        cairo_program.data = cairo_program.data + [0x10780017FFF7FFF, 0]
        memory = MemoryDict()
        runner = CairoRunner(
            program=cairo_program,
            layout=getattr(LAYOUTS, request.config.getoption(name="layout")),
            memory=memory,
            proof_mode=proof_mode,
            allow_missing_builtins=False,
        )
        dict_manager = DictManager()
        serde = serde_cls(
            runner.segments, cairo_program.identifiers, dict_manager, cairo_file
        )

        runner.program_base = runner.segments.add()
        runner.execution_base = runner.segments.add()
        for builtin_runner in runner.builtin_runners.values():
            builtin_runner.initialize_segments(runner)

        add_output = False
        stack = []

        # If we're in proof mode, all builtins are enabled by default. However, we don't use them in the entrypoint, nor do we return them at the end of the execution.
        # Because they're unused, we can simply put them in the stack (no impact on program execution), which is dumped into the execution public memory.
        # Note: if we tried to pass an included builtin here, it would fail, because we would try to access ptr-1 which is an invalid address. (see final_stack)
        if proof_mode:
            missing_builtins = [v for v in runner.builtin_runners.values() if not v.included]
            for builtin_runner in missing_builtins:
                builtin_runner.final_stack(runner, builtin_runner.base)
                stack.append(builtin_runner.base)


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
        gen_arg = (
            gen_arg_builder(dict_manager, runner.segments)
            if gen_arg_builder is not None
            else lambda _python_type, _value: runner.segments.gen_arg(_value)
        )
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

        # Initialize hint environment with injected functions, like in Rust (logger, serialize)
        context = {}
        prepare_context(lambda: context)

        runner.initialize_vm(
            hint_locals={
                "program_input": kwargs,
                "builtin_runners": runner.builtin_runners,
                "__dict_manager": dict_manager,
                "dict_manager": dict_manager,
                "serde": serde,
                "oracle": oracle(
                    cairo_program, serde, main_path, gen_arg, to_cairo_type
                ),
                "serialize": partial(
                    context["serialize"],
                    segments=runner.segments,
                    program_identifiers=cairo_program.identifiers,
                    dict_manager=dict_manager,
                ),
                **(hint_locals or {}),
            },
            static_locals={
                "debug_info": debug_info(cairo_program),
                "logger": context["logger"],
                **(static_locals or {}),
            },
            vm_class=VirtualMachine,
        )
        if not isinstance(runner.vm, VirtualMachine):
            raise ValueError("VM is not a VirtualMachine")

        # Get max_steps from pytest mark if available, otherwise use default
        max_steps = 1_000_000_000
        if hasattr(
            request.node, "get_closest_marker"
        ) and request.node.get_closest_marker("max_steps"):
            max_steps = request.node.get_closest_marker("max_steps").args[0]

        run_resources = RunResources(n_steps=max_steps)
        try:
            runner.run_until_pc(end, run_resources)
            if proof_mode:
                runner.run_for_steps(1)
            runner.original_steps = runner.vm.current_step
        except Exception as e:
            runner.end_run(disable_trace_padding=False)
            runner.relocate()
            trace = pl.DataFrame(
                [{"pc": x.pc, "ap": x.ap, "fp": x.fp} for x in runner.relocated_trace]
            )
            if coverage is not None:
                coverage(trace, PROGRAM_BASE)
            map_to_python_exception(e)

        runner.end_run(disable_trace_padding=False)
        cumulative_retdata_offsets = serde.get_offsets(return_data_types)
        first_return_data_offset = (
            cumulative_retdata_offsets[0] if cumulative_retdata_offsets else 0
        )
        if not isinstance(first_return_data_offset, int):
            raise ValueError("First return data offset is not an int")

        pointer = runner.vm.run_context.ap - first_return_data_offset  # First builtin

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

        trace = pl.DataFrame(
            [{"pc": x.pc, "ap": x.ap, "fp": x.fp} for x in runner.relocated_trace]
        )
        if coverage is not None:
            coverage(trace, PROGRAM_BASE)
        # Create a unique output stem for the given test by using the test file name, the entrypoint and the kwargs
        displayed_args = ""
        if kwargs:
            try:
                displayed_args = json.dumps(kwargs)
            except TypeError as e:
                logger.debug(f"Failed to serialize kwargs: {e}")
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
            stats, prof_dict = profile_from_trace(
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

        unfiltered_output = [
            serde.serialize(return_data_type, runner.vm.run_context.ap, offset)
            for offset, return_data_type in zip(
                cumulative_retdata_offsets, return_data_types
            )
        ]
        function_output = serde.filter_no_error_flag(unfiltered_output)
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

    return _run


def run_rust_vm(
    cairo_programs: List[Program],
    rust_programs: List[RustProgram],
    cairo_files: List[Path],
    main_paths: List[Tuple[str, ...]],
    request: FixtureRequest,
    gen_arg_builder: Optional[
        Callable[[DictManager, MemorySegmentManager], Callable]
    ] = None,
    to_python_type: Callable = to_python_type,
    serde_cls: Type[SerdeProtocol] = Serde,
    coverage: Optional[Callable[[pl.DataFrame, int], pl.DataFrame]] = None,
):
    """Helper function containing Rust VM implementation"""

    def _run(entrypoint, *args, **kwargs):
        cairo_program = cairo_programs[0]
        rust_program = rust_programs[0]
        cairo_file = cairo_files[0]
        main_path = main_paths[0]
        try:
            cairo_program.get_label(entrypoint)
        except Exception:
            # Entrypoint not found - try test program
            cairo_program = cairo_programs[1]
            rust_program = rust_programs[1]
            cairo_file = cairo_files[1]
            main_path = main_paths[1]

        _builtins, _implicit_args, _args, return_data_types = build_entrypoint(
            cairo_program, entrypoint, main_path, to_python_type
        )

        # Set program builtins based on the implicit args
        rust_program.builtins = [
            builtin
            for builtin in ALL_BUILTINS
            if builtin in [arg.replace("_ptr", "") for arg in _builtins]
        ]

        # Create runner
        runner = RustCairoRunner(
            program=rust_program,
            py_identifiers=cairo_program.identifiers,
            layout=getattr(LAYOUTS, request.config.getoption("layout")).layout_name,
            proof_mode=request.config.getoption("proof_mode"),
            allow_missing_builtins=False,
            enable_pythonic_hints=request.config.getoption("--log-cli-level")
            == "TRACE",
        )

        # Must be done right after runner creation to make sure the execution base is 1
        # See https://github.com/lambdaclass/cairo-vm/issues/1908
        runner.initialize_segments()

        # Fill runner's memory for args
        serde = serde_cls(
            runner.segments, cairo_program.identifiers, runner.dict_manager, cairo_file
        )
        stack = []
        # Handle other args, (implicit, explicit)
        gen_arg = (
            gen_arg_builder(runner.dict_manager, runner.segments)
            if gen_arg_builder is not None
            else lambda _python_type, _value: runner.segments.gen_arg(_value)
        )
        for i, (arg_name, python_type) in enumerate(
            [(k, v["python_type"]) for k, v in {**_implicit_args, **_args}.items()]
        ):
            arg_value = kwargs[arg_name] if arg_name in kwargs else args[i]
            stack.append(gen_arg(python_type, arg_value))

        # Initialize runner
        end = runner.initialize_vm(
            entrypoint=cairo_program.get_label(entrypoint),
            stack=stack,
            ordered_builtins=[
                builtin.replace("_ptr", "_builtin") for builtin in _builtins
            ],
        )

        # Bind Cairo's ASSERT_EQ instruction to a Python exception
        max_steps = 1_000_000_000
        if hasattr(
            request.node, "get_closest_marker"
        ) and request.node.get_closest_marker("max_steps"):
            max_steps = request.node.get_closest_marker("max_steps").args[0]
        try:
            runner.run_until_pc(end, RustRunResources(max_steps))
        except Exception as e:
            runner.relocate()
            if coverage is not None:
                coverage(runner.trace_df, PROGRAM_BASE)
            map_to_python_exception(e)

        cumulative_retdata_offsets = serde.get_offsets(return_data_types)
        first_return_data_offset = (
            cumulative_retdata_offsets[0] if cumulative_retdata_offsets else 0
        )
        runner.verify_auto_deductions()
        runner.read_return_values(first_return_data_offset)
        runner.verify_secure_runner()
        runner.relocate()
        print(len(runner.trace_df))

        if coverage is not None:
            coverage(runner.trace_df, PROGRAM_BASE)

        # Create a unique output stem for the given test by using the test file name, the entrypoint and the kwargs
        displayed_args = ""
        if kwargs:
            try:
                displayed_args = json.dumps(kwargs)
            except TypeError as e:
                logger.debug(f"Failed to serialize kwargs: {e}")
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
            stats, prof_dict = profile_from_trace(
                program=cairo_program, trace=runner.trace_df, program_base=PROGRAM_BASE
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
        function_output = serde_cls.filter_no_error_flag(unfiltered_output)
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

    return _run

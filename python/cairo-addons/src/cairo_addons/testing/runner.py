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
from typing import Callable, List, Optional, Tuple

import polars as pl
import starkware.cairo.lang.instances as LAYOUTS
from pytest import FixtureRequest
from starkware.cairo.common.dict import DictManager
from starkware.cairo.lang.builtins.all_builtins import ALL_BUILTINS
from starkware.cairo.lang.compiler.ast.cairo_types import (
    CairoType,
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
from starkware.cairo.lang.vm.security import verify_secure_runner
from starkware.cairo.lang.vm.utils import RunResources
from starkware.cairo.lang.vm.vm import VirtualMachine

from cairo_addons.hints.injected import prepare_context
from cairo_addons.profiler import profile_from_trace
from cairo_addons.rust_bindings.vm import CairoRunner as RustCairoRunner
from cairo_addons.rust_bindings.vm import Program as RustProgram
from cairo_addons.rust_bindings.vm import RunResources as RustRunResources
from cairo_addons.testing.errors import map_to_python_exception
from cairo_addons.testing.hints import debug_info, oracle
from cairo_addons.testing.utils import flatten
from tests.utils.args_gen import gen_arg as gen_arg_builder
from tests.utils.args_gen import to_cairo_type, to_python_type
from tests.utils.serde import Serde

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


def build_entrypoint(
    cairo_program: Program,
    entrypoint: str,
    main_path: Tuple[str, ...],
    to_python_type: Callable,
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
    coverage: Optional[Callable[[pl.DataFrame, int], pl.DataFrame]],
    hint_locals: Optional[dict] = None,
    static_locals: Optional[dict] = None,
):
    def _run(entrypoint, *args, **kwargs):
        # ============================================================================
        # STEP 1: SELECT PROGRAM AND PREPARE ENTRYPOINT METADATA
        # - Rationale: We need to determine which program contains the entrypoint (main or test)
        #   and extract its argument/return type metadata for type conversion and execution.
        # ============================================================================
        cairo_program = cairo_programs[0]
        cairo_file = cairo_files[0]
        main_path = main_paths[0]
        try:
            cairo_program.get_label(entrypoint)
        except Exception:
            cairo_program = cairo_programs[1]
            cairo_file = cairo_files[1]
            main_path = main_paths[1]

        _builtins, _implicit_args, _args, return_data_types = build_entrypoint(
            cairo_program, entrypoint, main_path, to_python_type
        )

        # ============================================================================
        # STEP 2: INITIALIZE RUNNER AND MEMORY ENVIRONMENT
        # - Rationale: Set up the CairoRunner with the program, layout, and memory.
        # We append a "jmp rel 0" instruction to enable looping at the end of the program, so that when ran in proof mode,
        # the number of executed steps can always be a power of two.
        # ============================================================================
        proof_mode = request.config.getoption("proof_mode")
        cairo_program.data = cairo_program.data + [0x10780017FFF7FFF, 0]  # jmp rel 0
        memory = MemoryDict()
        runner = CairoRunner(
            program=cairo_program,
            layout=getattr(LAYOUTS, request.config.getoption(name="layout")),
            memory=memory,
            proof_mode=proof_mode,
            allow_missing_builtins=False,
        )
        dict_manager = DictManager()
        serde = Serde(
            runner.segments, cairo_program.identifiers, dict_manager, cairo_file
        )
        runner.program_base = runner.segments.add()
        runner.execution_base = runner.segments.add()
        for builtin_runner in runner.builtin_runners.values():
            builtin_runner.initialize_segments(runner)

        # ============================================================================
        # STEP 3: BUILD INITIAL STACK WITH BUILTINS AND ARGUMENTS
        # - Rationale: Construct the stack with unused builtins (in proof mode - all builtins of the
        #   layout must be present) and all input arguments (implicit and explicit). This prepares the
        #   VM's execution context.
        # ============================================================================
        stack = []
        if proof_mode:
            missing_builtins = [
                v for v in runner.builtin_runners.values() if not v.included
            ]
            for builtin_runner in missing_builtins:
                # The builtin will never be used; so we can call final_stack here. This just returns the base pointer.
                builtin_runner.final_stack(runner, builtin_runner.base)
                stack.append(builtin_runner.base)

        for builtin_arg in _builtins:
            builtin_runner = runner.builtin_runners.get(
                builtin_arg.replace("_ptr", "_builtin")
            )
            if builtin_runner is None:
                raise ValueError(f"Builtin runner {builtin_arg} not found")
            stack.extend(builtin_runner.initial_stack())

        gen_arg = (
            gen_arg_builder(dict_manager, runner.segments)
            if gen_arg_builder is not None
            else lambda _python_type, _value: runner.segments.gen_arg(_value)
        )
        for i, (arg_name, python_type) in enumerate(
            [(k, v["python_type"]) for k, v in {**_implicit_args, **_args}.items()]
        ):
            arg_value = kwargs[arg_name] if arg_name in kwargs else args[i]
            stack.append(gen_arg(python_type, arg_value))

        # ============================================================================
        # STEP 4: SET UP EXECUTION CONTEXT AND LOAD MEMORY
        # - Rationale: Finalize the stack with return pointers, set initial VM registers,
        #   and load program/data into memory to start execution.
        # - Add the dummy last fp and pc to the public memory, so that the verifier can enforce
        #   [fp - 2] = fp.
        # ============================================================================
        return_fp = runner.execution_base + 2
        end = runner.program_base + len(runner.program.data) - 2  # Points to jmp rel 0
        stack = [return_fp, end] + stack + [return_fp, end]
        # All elements of the input stack are added to the execution public memory - required for proof mode
        runner.execution_public_memory = list(range(len(stack)))
        # Start the run at the offset of the entrypoint
        runner.initial_pc = runner.program_base + cairo_program.get_label(entrypoint)
        # Load the program into memory
        runner.load_data(runner.program_base, runner.program.data)
        runner.load_data(runner.execution_base, stack)  # Load the stack into memory
        # Set the initial frame pointer and argument pointer to the end of the stack
        runner.initial_fp = runner.initial_ap = runner.execution_base + len(stack)
        runner.initialize_zero_segment()

        # ============================================================================
        # STEP 5: CONFIGURE VM AND EXECUTE PROGRAM
        # - Rationale: Initialize the VM with hints, set execution limits, and run until the
        #   end address. Catch exceptions for debugging or coverage analysis.
        # ============================================================================
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
                    cairo_file=cairo_file,
                ),
                "gen_arg": partial(
                    context["_gen_arg"],
                    dict_manager,
                    runner.segments,
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

        max_steps = 1_000_000_000
        if hasattr(
            request.node, "get_closest_marker"
        ) and request.node.get_closest_marker("max_steps"):
            max_steps = request.node.get_closest_marker("max_steps").args[0]
        run_resources = RunResources(n_steps=max_steps)
        try:
            runner.run_until_pc(end, run_resources)
        except Exception as e:
            runner.end_run(disable_trace_padding=False)
            runner.relocate()
            trace = pl.DataFrame(
                [{"pc": x.pc, "ap": x.ap, "fp": x.fp} for x in runner.relocated_trace],
                schema=[("pc", pl.UInt32), ("ap", pl.UInt32), ("fp", pl.UInt32)],
            )
            if not request.config.getoption("no_coverage"):
                coverage(cairo_file, trace)
            map_to_python_exception(e)

        # ============================================================================
        # STEP 6: PROCESS RETURN VALUES AND FINALIZE EXECUTION
        # - `end_run`: relocates all memory segments and ensures that in proof mode, the number of executed steps is a power of two
        # - Once the run is over, we extract return data using serde, update the public memory in proof mode by adding the return data offsets to the public memory
        #   and performs security checks
        # ============================================================================
        runner.end_run(disable_trace_padding=False)
        cumulative_retdata_offsets = serde.get_offsets(return_data_types)
        first_return_data_offset = (
            cumulative_retdata_offsets[0] if cumulative_retdata_offsets else 0
        )
        if not isinstance(first_return_data_offset, int):
            raise ValueError("First return data offset is not an int")

        # Pointer to the first "builtin" - which are not considered as part of the return data
        pointer = runner.vm.run_context.ap - first_return_data_offset
        for arg in _builtins[::-1]:
            builtin_runner = runner.builtin_runners.get(arg.replace("_ptr", "_builtin"))
            if builtin_runner:
                pointer = builtin_runner.final_stack(runner, pointer)
            else:
                pointer -= 1

        if proof_mode:
            runner.execution_public_memory += list(
                range(
                    pointer.offset,
                    runner.vm.run_context.ap.offset - first_return_data_offset,
                )
            )
            runner.finalize_segments()
        verify_secure_runner(runner)
        runner.relocate()

        # ============================================================================
        # STEP 7: GENERATE OUTPUT FILES AND TRACE (IF REQUESTED)
        # ============================================================================
        trace = pl.DataFrame(
            [{"pc": x.pc, "ap": x.ap, "fp": x.fp} for x in runner.relocated_trace],
            schema=[("pc", pl.UInt32), ("ap", pl.UInt32), ("fp", pl.UInt32)],
        )
        if not request.config.getoption("no_coverage"):
            coverage(cairo_file, trace)

        # Create a unique output stem for the given test by using the test file name, the entrypoint and the kwargs
        displayed_args = ""
        if kwargs:
            try:
                displayed_args = json.dumps(kwargs)
            except TypeError:
                pass
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
                "scope", "primitive_call", "total_call", "total_cost", "cumulative_cost"
            ].sort("cumulative_cost", descending=True)
            logger.info(stats)
            stats.write_csv(output_stem.with_suffix(".csv"))
            marshal.dump(prof_dict, open(output_stem.with_suffix(".prof"), "wb"))

        if proof_mode:
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

        # ============================================================================
        # STEP 8: SERIALIZE AND RETURN OUTPUT
        #   For test purposes.
        # - Rationale: Convert Cairo return values to Python types, handle exceptions,
        #   and format the final output for the caller.
        # ============================================================================
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

        final_output = function_output
        return final_output[0] if len(final_output) == 1 else final_output

    return _run


def run_rust_vm(
    cairo_programs: List[Program],
    rust_programs: List[RustProgram],
    cairo_files: List[Path],
    main_paths: List[Tuple[str, ...]],
    request: FixtureRequest,
    coverage: Optional[Callable[[pl.DataFrame, int], pl.DataFrame]],
):
    def _run(entrypoint, *args, verify_squashed_dicts: bool = False, **kwargs):
        # ============================================================================
        # STEP 1: SELECT PROGRAM AND PREPARE ENTRYPOINT METADATA
        # - Rationale: Determine which program contains the entrypoint (main or test)
        #   and extract its argument/return type metadata for type conversion and execution.
        #   Set the program's builtins based on the entrypoint's implicit args.
        # ============================================================================
        cairo_program = cairo_programs[0]
        rust_program = rust_programs[0]
        cairo_file = cairo_files[0]
        main_path = main_paths[0]

        try:
            cairo_program.get_label(entrypoint)
        except Exception:
            cairo_program = cairo_programs[1]
            rust_program = rust_programs[1]
            cairo_file = cairo_files[1]
            main_path = main_paths[1]

        _builtins, _implicit_args, _args, return_data_types = build_entrypoint(
            cairo_program, entrypoint, main_path, to_python_type
        )
        cairo_program.data = cairo_program.data + [0x10780017FFF7FFF, 0]  # jmp rel 0
        rust_program.builtins = [
            builtin
            for builtin in ALL_BUILTINS
            if builtin in [arg.replace("_ptr", "") for arg in _builtins]
        ]

        # ============================================================================
        # STEP 2: INITIALIZE RUNNER AND MEMORY ENVIRONMENT
        # - Rationale: Set up the RustCairoRunner with the program, layout, and memory.
        #   Unlike Python VM, we don’t append "jmp rel 0" here as Rust handles proof mode differently.
        # ============================================================================
        proof_mode = request.config.getoption("proof_mode")
        enable_traces = request.config.getoption("--log-cli-level") == "TRACE"
        runner = RustCairoRunner(
            program=rust_program,
            py_identifiers=cairo_program.identifiers,
            program_input=kwargs,
            layout=getattr(LAYOUTS, request.config.getoption("layout")).layout_name,
            proof_mode=proof_mode,
            allow_missing_builtins=False,
            enable_traces=enable_traces,
            ordered_builtins=_builtins,
            cairo_file=cairo_file,
        )
        serde = Serde(
            runner.segments, cairo_program.identifiers, runner.dict_manager, cairo_file
        )
        # Must be done right after runner creation to make sure the execution base is 1
        # See https://github.com/lambdaclass/cairo-vm/issues/1908
        runner.initialize_segments()  # Sets program_base and execution_base

        # ============================================================================
        # STEP 3: BUILD INITIAL STACK WITH BUILTINS AND ARGUMENTS
        # - Rationale: Construct the stack with unused builtins (in proof mode) and all input
        #   arguments (implicit and explicit). This prepares the VM's execution context.
        # ============================================================================
        stack = []
        if proof_mode:
            # In proof mode, Rust initializes all layout builtins; we mimic Python’s behavior
            builtin_runners = runner.builtin_runners
            missing_builtins = [
                v for k, v in builtin_runners.items() if not v["included"]
            ]
            for builtin_runner in missing_builtins:
                stack.extend(
                    builtin_runner["final_stack"]
                )  # Base pointer for unused builtins

        for builtin_arg in _builtins:
            builtin_name = builtin_arg.replace("_ptr", "_builtin")
            builtin_runner = runner.builtin_runners.get(builtin_name)
            if builtin_runner is None:
                raise ValueError(f"Builtin runner {builtin_arg} not found")
            stack.extend(builtin_runner["initial_stack"])

        gen_arg = (
            gen_arg_builder(runner.dict_manager, runner.segments)
            if gen_arg_builder is not None
            else lambda _python_type, _value: runner.segments.gen_arg(_value)
        )
        for i, (arg_name, python_type) in enumerate(
            [(k, v["python_type"]) for k, v in {**_implicit_args, **_args}.items()]
        ):
            arg_value = kwargs[arg_name] if arg_name in kwargs else args[i]
            stack.extend(flatten(gen_arg(python_type, arg_value)))

        # ============================================================================
        # STEP 4: SET UP EXECUTION CONTEXT AND LOAD MEMORY
        # - Rationale: Finalize the stack with return pointers, set initial VM registers,
        #   and load program/data into memory to start execution.
        # - Add the dummy last fp and pc to the public memory, so that the verifier can enforce
        #   [fp - 2] = fp.
        # ============================================================================
        return_fp = runner.execution_base + 2
        end = runner.program_base + runner.program_len - 2  # Points to jmp rel 0
        stack = [return_fp, end] + stack + [return_fp, end]
        runner.execution_public_memory = list(
            range(len(stack))
        )  # All elements of the input stack are added to the execution public memory - required for proof mode
        runner.initial_pc = runner.program_base + cairo_program.get_label(
            entrypoint
        )  # Start the run at the offset of the entrypoint
        runner.load_program_data(runner.program_base)  # Load the program into memory
        runner.load_data(runner.execution_base, stack)  # Load the stack into memory
        runner.initial_fp = runner.initial_ap = runner.execution_base + len(
            stack
        )  # Set the initial frame pointer and argument pointer to the end of the stack

        runner.initialize_vm()

        # ============================================================================
        # STEP 5: CONFIGURE VM AND EXECUTE PROGRAM
        # - Rationale: Execute the program until the end address, catching exceptions
        #   for debugging or coverage analysis. Rust handles hint initialization internally.
        # ============================================================================
        max_steps = 1_000_000_000
        if hasattr(
            request.node, "get_closest_marker"
        ) and request.node.get_closest_marker("max_steps"):
            max_steps = request.node.get_closest_marker("max_steps").args[0]
        run_resources = RustRunResources(max_steps)
        try:
            runner.run_until_pc(end, run_resources)
        except Exception as e:
            runner.relocate()
            if not request.config.getoption("no_coverage"):
                coverage(cairo_file, runner.trace_df)
            map_to_python_exception(e)

        # ============================================================================
        # STEP 6: PROCESS RETURN VALUES AND FINALIZE EXECUTION
        # - Rationale: Extract return data using serde, update public memory in proof mode,
        #   and verify the runner’s security before relocation.
        # ============================================================================
        cumulative_retdata_offsets = serde.get_offsets(return_data_types)
        first_return_data_offset = (
            cumulative_retdata_offsets[0] if cumulative_retdata_offsets else 0
        )
        if not isinstance(first_return_data_offset, int):
            raise ValueError("First return data offset is not an int")

        runner.verify_auto_deductions()
        pointer = runner.read_return_values(first_return_data_offset)

        if proof_mode:
            runner.update_execution_public_memory(pointer, first_return_data_offset)
            runner.finalize_segments()

        runner.verify_secure_runner()
        runner.relocate()

        if verify_squashed_dicts:
            # Ensure all dicts are squashed properly
            # (not implemented in python vm)
            runner.verify_squashed_dicts()

        # ============================================================================
        # STEP 7: GENERATE OUTPUT FILES AND TRACE (IF REQUESTED)
        # - Rationale: Save trace, memory, and profiling data based on config options for
        #   debugging, proof generation, or performance analysis.
        # ============================================================================
        if not request.config.getoption("no_coverage"):
            coverage(cairo_file, runner.trace_df)

        # Create a unique output stem for the given test by using the test file name, the entrypoint and the kwargs
        displayed_args = ""
        if kwargs:
            try:
                displayed_args = json.dumps(kwargs)
            except TypeError:
                pass
        output_stem = str(
            request.node.path.parent
            / f"{request.node.path.stem}_{entrypoint}_{displayed_args}"
        )
        output_stem = str(
            request.node.path.parent
            / f"{request.node.path.stem}_{entrypoint}_{displayed_args}"
        )
        output_stem = Path(
            f"{output_stem[:160]}_{int(time_ns())}_{md5(output_stem.encode()).digest().hex()[:8]}"
        )

        if request.config.getoption("profile_cairo"):
            stats, prof_dict = profile_from_trace(
                program=cairo_program, trace=runner.trace_df, program_base=PROGRAM_BASE
            )
            stats = stats[
                "scope", "primitive_call", "total_call", "total_cost", "cumulative_cost"
            ].sort("cumulative_cost", descending=True)
            logger.info(stats)
            stats.write_csv(output_stem.with_suffix(".csv"))
            marshal.dump(prof_dict, open(output_stem.with_suffix(".prof"), "wb"))

        if proof_mode:
            runner.write_binary_trace(str(output_stem.with_suffix(".trace")))
            runner.write_binary_memory(
                str(output_stem.with_suffix(".memory")),
                math.ceil(cairo_program.prime.bit_length() / 8),
            )
            runner.write_binary_air_public_input(
                str(output_stem.with_suffix(".air_public_input.json"))
            )
            runner.write_binary_air_private_input(
                str(output_stem.with_suffix(".trace")),
                str(output_stem.with_suffix(".memory")),
                str(output_stem.with_suffix(".air_private_input.json")),
            )

        # ============================================================================
        # STEP 8: SERIALIZE AND RETURN OUTPUT
        # - Rationale: Convert Cairo return values to Python types, handle exceptions,
        #   and format the final output for the caller.
        # ============================================================================
        unfiltered_output = [
            serde.serialize(return_data_type, runner.ap, offset)
            for offset, return_data_type in zip(
                cumulative_retdata_offsets, return_data_types
            )
        ]
        function_output = Serde.filter_no_error_flag(unfiltered_output)
        exceptions = [
            val
            for val in flatten(function_output)
            if hasattr(val, "__class__") and issubclass(val.__class__, Exception)
        ]
        if exceptions:
            raise exceptions[0]

        final_output = function_output

        return final_output[0] if len(final_output) == 1 else final_output

    return _run

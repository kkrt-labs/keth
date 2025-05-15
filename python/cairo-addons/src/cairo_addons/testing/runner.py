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

# function arguments that are not builtins, but we want to generate a
# segment for.
SEGMENT_PTR_NAMES = {"keccak_ptr", "blake2s_ptr"}


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

    _implicit_args = {}

    for k, v in implicit_args.items():
        is_builtin = (
            any(builtin == k.replace("_ptr", "") for builtin in ALL_BUILTINS)
            and k not in SEGMENT_PTR_NAMES
        )
        if is_builtin:
            arg_info = {}
        else:
            arg_info = {
                "python_type": to_python_type(
                    resolve_main_path(main_path)(v.cairo_type)
                ),
                "cairo_type": v.cairo_type,
            }

        _implicit_args[k] = arg_info

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

    # Construct the full list of return data types with their names and includes flags
    # This list must maintain the order of arguments as defined in the Cairo function signature
    # (implicit args first, then explicit return type)

    # used to get the size of the types.
    serde = Serde(None, cairo_program.identifiers, None, None)

    # Process implicit arguments using a list comprehension
    implicit_arg_info = [
        (
            {
                "name": arg_name,
                "type": {},
                "include": False,
                "size": None,  # Size is handled internally by builtin runner
            }
            if is_actual_builtin(arg_name)
            else {
                "name": arg_name,
                "type": arg_info["cairo_type"],
                "include": arg_name not in SEGMENT_PTR_NAMES,
                "size": serde.get_offset(arg_info["cairo_type"]),
            }
        )
        for arg_name, arg_info in _implicit_args.items()
    ]

    # Prepare explicit return type info (if it exists and is not an empty tuple)
    explicit_return_item = []
    if not (
        isinstance(explicit_return_data, TypeTuple)
        and len(explicit_return_data.members) == 0
    ):
        explicit_return_item = [
            {
                "name": None,  # Explicit return doesn't have a name
                "type": explicit_return_data,
                "include": True,  # Always include explicit return
                "size": serde.get_offset(explicit_return_data),
            }
        ]

    # Combine implicit and explicit return info
    return_data_info = implicit_arg_info + explicit_return_item

    # Fix builtins runner based on the implicit args since the compiler doesn't find them
    cairo_program.builtins = [
        builtin
        for builtin in ALL_BUILTINS
        if is_actual_builtin(f"{builtin}_ptr")
        and f"{builtin}_ptr" in list(_implicit_args.keys())
    ]

    return _implicit_args, _args, return_data_info


def is_actual_builtin(arg_name: str) -> bool:
    """Checks if an argument name corresponds to a Cairo builtin, excluding special segment pointers."""
    return (
        any(f"{builtin}_ptr" == arg_name for builtin in ALL_BUILTINS)
        and arg_name not in SEGMENT_PTR_NAMES
    )


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

        _implicit_args, _args, return_data_info = build_entrypoint(
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
        # STEP 3: BUILD INITIAL STACK
        # - Rationale: Generate stack components for all arguments (implicit args, explicit args)
        #   respecting the order defined in the Cairo function signature.
        #   Handle builtins and special segment pointers accordingly.
        #   Ensure consistency with Rust VM stack building logic.
        # ============================================================================
        stack_prefix = []
        if proof_mode:
            # Add base pointers for builtins *not* used by the function but required by the layout
            missing_builtins = [
                v for v in runner.builtin_runners.values() if not v.included
            ]
            for builtin_runner in missing_builtins:
                # The builtin will never be used; so we can call final_stack here. This just returns the base pointer.
                builtin_runner.final_stack(runner, builtin_runner.base)
                stack_prefix.append(builtin_runner.base)  # Add to final stack directly

        # Prepare argument generation function
        gen_arg = (
            gen_arg_builder(dict_manager, runner.segments)
            if gen_arg_builder is not None
            else lambda _python_type, _value: runner.segments.gen_arg(_value)
        )

        ordered_components = []
        processed_kwargs = set()
        arg_idx = 0  # Index for consuming positional args from *args
        all_args = {**_implicit_args, **_args}

        for arg_name, arg_info in all_args.items():
            python_type = arg_info.get("python_type")
            component = None

            if is_actual_builtin(arg_name):
                builtin_runner = runner.builtin_runners.get(
                    arg_name.replace("_ptr", "_builtin")
                )
                if builtin_runner and builtin_runner.included:
                    # Builtins included in the function signature contribute their initial stack
                    component = builtin_runner.initial_stack()
                elif (
                    builtin_runner
                    and proof_mode
                    and arg_name.replace("_ptr", "_builtin") in runner.layout_builtins
                ):
                    # If proof_mode requires all layout builtins, add base even if not in signature
                    # This case might indicate an issue if build_entrypoint is correct
                    logger.warning(
                        f"Builtin {arg_name} required by layout but not marked as included by function signature."
                    )
                    component = [builtin_runner.base]
                elif not builtin_runner:
                    raise ValueError(
                        f"Builtin runner for {arg_name} not found despite being in signature."
                    )

            elif arg_name in SEGMENT_PTR_NAMES:
                # Allocate a new segment for non-builtin pointers
                segment_ptr = runner.segments.add()
                component = [segment_ptr]

            else:
                # Regular argument (implicit value arg or explicit arg)
                arg_value = None
                if arg_name in kwargs:
                    arg_value = kwargs[arg_name]
                    processed_kwargs.add(arg_name)
                elif arg_idx < len(args):
                    # Consume positional arguments for non-keyword args
                    arg_value = args[arg_idx]
                    arg_idx += 1
                else:
                    # Argument value not found
                    raise TypeError(f"Missing value for argument '{arg_name}'")

                # Generate the Cairo value for the argument
                component = flatten(gen_arg(python_type, arg_value))

            if component is not None:
                ordered_components.extend(component)

        # ============================================================================
        # STEP 4: SET UP EXECUTION CONTEXT AND LOAD MEMORY
        # - Rationale: Finalize the stack with return pointers, set initial VM registers,
        #   and load program/data into memory to start execution.
        # - Add the dummy last fp and pc to the public memory, so that the verifier can enforce
        #   [fp - 2] = fp.
        # ============================================================================
        return_fp = runner.execution_base + 2
        end = runner.program_base + len(runner.program.data) - 2  # Points to jmp rel 0
        # Assemble final stack: [ret_fp, ret_pc] + proof_mode_prefix + ordered_components + [ret_fp, ret_pc]
        # Note: The order of stack elements is crucial for the VM.
        stack = stack_prefix + ordered_components
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
                "debug_info": debug_info(cairo_program.debug_info),
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
        # - Note: Return value processing logic should align with Rust VM's _read_return_values.
        # ============================================================================
        runner.end_run(disable_trace_padding=False)
        cairo_types = [item["type"] for item in return_data_info]
        cumulative_retdata_offsets = serde.get_offsets(cairo_types)
        first_return_data_offset = (
            cumulative_retdata_offsets[0] if cumulative_retdata_offsets else 0
        )
        if not isinstance(first_return_data_offset, int):
            raise ValueError("First return data offset is not an int")

        pointer = runner.vm.run_context.ap
        for arg in return_data_info[::-1]:
            arg_name = arg["name"] or ""
            if is_actual_builtin(arg_name):
                builtin_runner = runner.builtin_runners.get(
                    arg_name.replace("_ptr", "_builtin")
                )
                if builtin_runner:
                    pointer = builtin_runner.final_stack(runner, pointer)
                else:
                    pointer -= 1
            else:
                pointer -= arg["size"] or 1

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
        function_output = []

        # Simplified filtering based on the include flag
        for return_item, offset in zip(return_data_info, cumulative_retdata_offsets):
            if return_item["include"]:
                serialized_value = serde.serialize(
                    return_item["type"], runner.vm.run_context.ap, offset
                )
                function_output.append(serialized_value)

        # Filter any error flags or None values if needed
        function_output = Serde.filter_no_error_flag(function_output)

        exceptions = [
            val
            for val in flatten(function_output)
            if hasattr(val, "__class__") and issubclass(val.__class__, Exception)
        ]
        if exceptions:
            raise exceptions[0]

        return function_output[0] if len(function_output) == 1 else function_output

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

        _implicit_args, _args, return_data_info = build_entrypoint(
            cairo_program, entrypoint, main_path, to_python_type
        )
        cairo_program.data = cairo_program.data + [0x10780017FFF7FFF, 0]  # jmp rel 0
        rust_program.builtins = [
            builtin
            for builtin in ALL_BUILTINS
            if is_actual_builtin(f"{builtin}_ptr")
            and f"{builtin}_ptr" in list(_implicit_args.keys())
        ]

        # ============================================================================
        # STEP 2: INITIALIZE RUNNER AND MEMORY ENVIRONMENT
        # - Rationale: Set up the RustCairoRunner with the program, layout, and memory.
        #   Unlike Python VM, we don't append "jmp rel 0" here as Rust handles proof mode differently.
        # ============================================================================
        proof_mode = request.config.getoption("proof_mode")
        enable_traces = request.config.getoption("--log-cli-level") == "TRACE"

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
        output_stem = Path(
            f"{output_stem[:160]}_{int(time_ns())}_{md5(output_stem.encode()).digest().hex()[:8]}"
        )
        runner = RustCairoRunner(
            program=rust_program,
            py_identifiers=cairo_program.identifiers,
            program_input=kwargs,
            layout=getattr(LAYOUTS, request.config.getoption("layout")).layout_name,
            proof_mode=proof_mode,
            allow_missing_builtins=False,
            enable_traces=enable_traces,
            return_data_info=[
                (item["name"] or "", item["size"]) for item in return_data_info
            ],
            cairo_file=cairo_file,
            py_debug_info=cairo_program.debug_info,
            output_path=output_stem,
        )
        serde = Serde(
            runner.segments, cairo_program.identifiers, runner.dict_manager, cairo_file
        )
        # Must be done right after runner creation to make sure the execution base is 1
        # See https://github.com/lambdaclass/cairo-vm/issues/1908
        runner.initialize_segments()  # Sets program_base and execution_base

        # ============================================================================
        # STEP 3: BUILD INITIAL STACK WITH BUILTINS AND ARGUMENTS
        # - Rationale: Construct the stack respecting the Cairo function signature order,
        #   including builtins, special segment pointers, and other arguments.
        #   Ensure consistency with Python VM stack building logic.
        # ============================================================================
        stack_prefix = []
        if proof_mode:
            # Add base pointers for builtins *not* used by the function but required by the layout
            missing_builtins = [
                v
                for k, v in runner.builtin_runners.items()
                if not v["included"]  # Check 'included' flag safely
                # Add condition to check if it's part of the expected layout if needed
            ]
            for builtin_runner in missing_builtins:
                # Use 'final_stack' which might be the base ptr list, or fallback to 'base' if available
                # Ensure it returns a list
                base_ptr_comp = builtin_runner["final_stack"]
                if (
                    base_ptr_comp and base_ptr_comp[0] is not None
                ):  # Check if base exists
                    stack_prefix.extend(base_ptr_comp)
                else:
                    logger.warning(
                        f"Could not determine base pointer for missing proof-mode builtin: {builtin_runner['name']}"
                    )

        # Prepare argument generation function
        gen_arg = (
            gen_arg_builder(runner.dict_manager, runner.segments)
            if gen_arg_builder is not None
            else lambda _python_type, _value: runner.segments.gen_arg(_value)
        )

        ordered_components = []
        arg_idx = 0
        all_args = {
            **_implicit_args,
            **_args,
        }

        for arg_name, arg_info in all_args.items():
            python_type = arg_info.get("python_type")
            component = None

            if is_actual_builtin(arg_name):
                builtin_name = arg_name.replace("_ptr", "_builtin")
                builtin_runner = runner.builtin_runners.get(builtin_name)
                if builtin_runner and builtin_runner["included"]:
                    # Builtins included in the function signature contribute their initial stack
                    component = builtin_runner["initial_stack"]
                # Note: Proof mode base pointers for *missing* builtins added in stack_prefix
                elif not builtin_runner:
                    raise ValueError(f"Builtin runner for {arg_name} not found.")

            elif arg_name in SEGMENT_PTR_NAMES:
                # Allocate a new segment for non-builtin special pointers
                segment_ptr = runner.segments.add()
                component = [segment_ptr]

            else:
                # Regular argument (implicit value arg or explicit arg)
                arg_value = None
                if arg_name in kwargs:
                    arg_value = kwargs[arg_name]
                elif arg_idx < len(args):
                    arg_value = args[arg_idx]
                    arg_idx += 1
                else:
                    raise TypeError(f"Missing value for argument '{arg_name}'")

                # Generate the Cairo value
                component = flatten(gen_arg(python_type, arg_value))

            if component is not None:
                ordered_components.extend(component)

        # ============================================================================
        # STEP 4: SET UP EXECUTION CONTEXT AND LOAD MEMORY
        # - Rationale: Finalize the stack with return pointers, set initial VM registers,
        #   and load program/data into memory to start execution.
        # - Add the dummy last fp and pc to the public memory, so that the verifier can enforce
        #   [fp - 2] = fp.
        # ============================================================================
        return_fp = runner.execution_base + 2
        end = runner.program_base + runner.program_len - 2  # Points to jmp rel 0
        # Assemble final stack: [ret_fp, ret_pc] + proof_mode_prefix + ordered_components + [ret_fp, ret_pc]
        # Note: The order of stack elements is crucial for the VM.
        stack = stack_prefix + ordered_components
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
        #   and verify the runner's security before relocation.
        #   Ensure consistency with Python VM return value processing.
        # ============================================================================
        cairo_types = [item["type"] for item in return_data_info]
        cumulative_retdata_offsets = serde.get_offsets(cairo_types)
        first_return_data_offset = (
            cumulative_retdata_offsets[0] if cumulative_retdata_offsets else 0
        )
        if not isinstance(first_return_data_offset, int):
            raise ValueError("First return data offset is not an int")

        runner.verify_auto_deductions()
        pointer = runner.read_return_values()

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

        # ============================================================================
        # STEP 8: SERIALIZE AND RETURN OUTPUT
        # - Rationale: Convert Cairo return values to Python types, handle exceptions,
        #   and format the final output for the caller.
        # ============================================================================
        function_output = []

        # Simplified filtering based on the include flag
        for return_item, offset in zip(return_data_info, cumulative_retdata_offsets):
            if return_item["include"]:
                serialized_value = serde.serialize(
                    return_item["type"], runner.ap, offset
                )
                function_output.append(serialized_value)

        # Filter any error flags or None values if needed
        function_output = Serde.filter_no_error_flag(function_output)

        exceptions = [
            val
            for val in flatten(function_output)
            if hasattr(val, "__class__") and issubclass(val.__class__, Exception)
        ]
        if exceptions:
            raise exceptions[0]

        return function_output[0] if len(function_output) == 1 else function_output

    return _run

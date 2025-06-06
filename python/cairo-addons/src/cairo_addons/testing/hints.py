import contextlib
import re
from contextlib import contextmanager
from importlib import import_module
from typing import List, Optional
from unittest.mock import patch

from starkware.cairo.lang.compiler.debug_info import DebugInfo
from starkware.cairo.lang.compiler.program import CairoHint, Program

from cairo_addons.hints import implementations
from cairo_addons.rust_bindings.vm import Program as RustProgram


def debug_info(debug_info: Optional[DebugInfo]):
    def _debug_info(pc):
        if debug_info is None:
            raise ValueError("Program debug info is not set")

        if (
            instruction_location := debug_info.instruction_locations.get(pc.offset)
        ) is None:
            raise ValueError("Instruction location not found")

        print(instruction_location.inst.to_string_with_content(""))

    return _debug_info


@contextmanager
def patch_hint(
    cairo_programs: List[Program],
    rust_programs: List[RustProgram],
    hint: str,
    new_hint: str,
    scope: Optional[str] = None,
):
    """
    Temporarily patches a Cairo hint in a list of Python and Rust programs with a new hint code.

    This function can handle two types of hints:
    1. Nondet hints in the format: 'nondet %{arg%};'
    2. Regular hints with arbitrary code

    When patching nondet hints, the function will automatically look for the memory assignment
    pattern 'memory[fp + <i>] = to_felt_or_relocatable(arg)' and replace the argument.

    Args:
        cairo_programs: A list of Cairo `Program` objects (Python-based).
        rust_programs: A list of `RustProgram` objects (Rust-based).
        hint: The original hint code to replace.
        new_hint: The new hint code to use.
        scope: Optional scope name to restrict which hints are patched.

    Yields:
        None (modifications are made in place to `cairo_programs` and `rust_programs`).
    Raises:
        ValueError: If the specified hint is not found in the program
    """
    with contextlib.ExitStack() as stack:
        # Determine if we're dealing with nondet hints
        orig_nondet_arg = get_nondet_arg(hint)
        new_nondet_arg = get_nondet_arg(new_hint)

        # Patch Python Program hints
        patched_hints = patch_program_hints(
            cairo_programs, hint, new_hint, scope, orig_nondet_arg, new_nondet_arg
        )
        for program, new_hints in zip(cairo_programs, patched_hints):
            stack.enter_context(patch.object(program, "hints", new=new_hints))

        # Patch Rust Program hints
        if rust_programs:
            original_hint_code = implementations.get(hint.strip(), hint.strip())
            final_hint_code = new_hint

            # If it's a nondet hint, we need to transform the memory assignment pattern
            if orig_nondet_arg and new_nondet_arg:
                final_hint_code = transform_nondet_hint(
                    original_hint_code, orig_nondet_arg, new_nondet_arg
                )

            for rust_program in rust_programs:
                rust_program.replace_hints(original_hint_code, final_hint_code)

            # Register cleanup to restore rust_programs
            def restore_rust_programs():
                for rust_program in rust_programs:
                    rust_program.replace_hints(final_hint_code, original_hint_code)

            stack.callback(restore_rust_programs)

        yield


def get_nondet_arg(hint_code: str) -> Optional[str]:
    """Extract argument from nondet hint if it is one, otherwise return None."""
    if match := re.match(r"nondet %{(.+)%};", hint_code.strip()):
        return match.group(1).strip()
    return None


def parse_fp_assignment_hint(hint_code: str) -> tuple[Optional[str], Optional[str]]:
    """Extract memory location and argument from an fp assignment hint."""
    if match := re.match(r"memory\[(.+)\] = to_felt_or_relocatable\((.+)\)", hint_code):
        return match.group(1), match.group(2).strip()
    return None, None


def transform_nondet_hint(hint_code: str, orig_arg: str, new_arg: str) -> str:
    """Transform a nondet hint by replacing the original argument with the new one in memory assignments."""
    mem_loc, arg = parse_fp_assignment_hint(hint_code)
    if arg == orig_arg:
        return f"memory[{mem_loc}] = to_felt_or_relocatable({new_arg})"
    return hint_code


def patch_program_hints(
    programs: List[Program],
    hint: str,
    new_hint: str,
    scope: Optional[str],
    orig_nondet_arg: Optional[str],
    new_nondet_arg: Optional[str],
) -> List[dict]:
    """
    Patch hints in a list of Python `Program` objects.

    Args:
        programs: A list of Python `Program` objects.
        hint: The original hint code to replace.
        new_hint: The new hint code to use.
        scope: Optional scope name to restrict which hints are patched.
        orig_nondet_arg: Original nondet argument if it's a nondet hint.
        new_nondet_arg: New nondet argument if it's a nondet hint.

    Returns:
        List of patched hints dictionaries for each program.
    """
    patched_programs_hints = [{} for _ in programs]

    for i, program in enumerate(programs):
        patched_hints = {}
        for k, hint_list in program.hints.items():
            new_hints = []
            for hint_ in hint_list:
                # Skip hints not in specified scope
                if scope is not None and scope not in str(hint_.accessible_scopes[-1]):
                    new_hints.append(hint_)
                    continue

                if orig_nondet_arg and new_nondet_arg:
                    # Handle nondet hint patching
                    new_hints.append(
                        CairoHint(
                            accessible_scopes=hint_.accessible_scopes,
                            flow_tracking_data=hint_.flow_tracking_data,
                            code=transform_nondet_hint(
                                hint_.code, orig_nondet_arg, new_nondet_arg
                            ),
                        )
                    )
                else:
                    # Handle regular hint patching
                    if hint_.code.strip() == implementations.get(
                        hint.strip(), hint.strip()
                    ):
                        new_hints.append(
                            CairoHint(
                                accessible_scopes=hint_.accessible_scopes,
                                flow_tracking_data=hint_.flow_tracking_data,
                                code=new_hint,
                            )
                        )
                    else:
                        new_hints.append(hint_)
            patched_hints[k] = new_hints

        if patched_hints == program.hints:
            raise ValueError(f"Hint\n\n{hint}\n\nnot found in program hints.")

        patched_programs_hints[i] = patched_hints

    return patched_programs_hints


@contextmanager
def insert_hint(program, location: str, hint):
    """
    Insert a hint at a given location in the program.

    The location should be file_name:line_number.

    """
    instructions = {
        index: loc
        for index, loc in program.debug_info.instruction_locations.items()
        if location in str(loc.inst)
    }
    if not instructions:
        raise ValueError(f"Location {location} not found in program.")
    pc, instruction = list(instructions.items())[0]
    hint = CairoHint(
        accessible_scopes=instruction.accessible_scopes,
        flow_tracking_data=instruction.flow_tracking_data,
        code=hint,
    )
    new_hints = program.hints.copy()
    new_hints[pc] = [*new_hints.get(pc, []), hint]
    with (
        patch.object(instruction, "hints", new=new_hints.get(pc, [])),
        patch.object(program, "hints", new=new_hints),
    ):
        yield


def oracle(program, serde, main_path, gen_arg, to_cairo_type):

    def _factory(ids, reference: Optional[str] = None):
        full_path = (
            reference.split(".")
            if reference is not None
            else list(program.hints.values())[-1][0].accessible_scopes[-1].path
        )
        if "__main__" in full_path:
            full_path = main_path + full_path[full_path.index("__main__") + 1 :]

        mod = import_module(".".join(full_path[:-1]))
        target = getattr(mod, full_path[-1])
        from inspect import signature

        sig = signature(target)
        args = []
        for name, type_ in sig.parameters.items():
            args += [
                serde.serialize(
                    to_cairo_type(program, type_._annotation),
                    getattr(ids, name).address_,
                    shift=0,
                )
            ]
        return gen_arg(sig.return_annotation, target(*args))

    return _factory

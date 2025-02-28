import contextlib
from contextlib import contextmanager
from importlib import import_module
from typing import List, Optional
from unittest.mock import patch

from starkware.cairo.lang.compiler.program import CairoHint, Program

from cairo_addons.hints import implementations


def debug_info(program: Program):
    def _debug_info(pc):
        if program.debug_info is None:
            raise ValueError("Program debug info is not set")

        if (
            instruction_location := program.debug_info.instruction_locations.get(
                pc.offset
            )
        ) is None:
            raise ValueError("Instruction location not found")

        print(instruction_location.inst.to_string_with_content(""))

    return _debug_info


@contextmanager
def patch_hint(
    programs: List[Program], hint: str, new_hint: str, scope: Optional[str] = None
):
    """
    Temporarily patches a Cairo hint in a program with a new hint code.

    This function can handle two types of hints:
    1. Nondet hints in the format: 'nondet %{arg%};'
    2. Regular hints with arbitrary code

    When patching nondet hints, the function will automatically look for the memory assignment
    pattern 'memory[fp + <i>] = to_felt_or_relocatable(arg)' and replace the argument.

    Args:
        program: The Cairo program containing the hints to patch
        hint: The original hint code to replace. Can be either a regular hint or a nondet hint.
        new_hint: The new hint code to use. For nondet hints, this should be a new nondet hint.
        scope: Optional scope name to restrict which hints are patched. If provided,
               only hints within matching scopes will be modified

    Raises:
        ValueError: If the specified hint is not found in the program

    Example:
        # Replace a nondet hint
        with patch_hint(program, 'nondet %{x%};', 'nondet %{y%};'):
            ...

        # Replace a regular hint
        with patch_hint(program, 'ids.x = 5', 'ids.x = 10'):
            ...

        # Replace hint only in specific scope
        with patch_hint(program, 'ids.x = 5', 'ids.x = 10', scope='my_function'):
            ...
    """
    import re

    def get_nondet_arg(hint_code: str) -> Optional[str]:
        """Extract argument from nondet hint if it is one, otherwise return None."""
        if match := re.match(r"nondet %{(.+)%};", hint_code.strip()):
            return match.group(1).strip()
        return None

    def parse_fp_assignment_hint(hint_code: str) -> tuple[Optional[str], Optional[str]]:
        """Extract memory location and argument from an fp assignment hint."""
        if match := re.match(
            r"memory\[(.+)\] = to_felt_or_relocatable\((.+)\)", hint_code
        ):
            return match.group(1), match.group(2).strip()
        return None, None

    orig_nondet_arg = get_nondet_arg(hint)
    new_nondet_arg = get_nondet_arg(new_hint)

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

                if orig_nondet_arg:
                    # Handle nondet hint patching
                    mem_loc, arg = parse_fp_assignment_hint(hint_.code)
                    if arg == orig_nondet_arg:
                        new_hints.append(
                            CairoHint(
                                accessible_scopes=hint_.accessible_scopes,
                                flow_tracking_data=hint_.flow_tracking_data,
                                code=f"memory[{mem_loc}] = to_felt_or_relocatable({new_nondet_arg})",
                            )
                        )
                    else:
                        new_hints.append(hint_)
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

    # Create context managers for all programs
    with contextlib.ExitStack() as stack:
        for program, patched_hints in zip(programs, patched_programs_hints):
            stack.enter_context(patch.object(program, "hints", new=patched_hints))
        yield


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

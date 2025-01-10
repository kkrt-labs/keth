from collections import defaultdict
from contextlib import contextmanager
from dataclasses import asdict, is_dataclass
from importlib import import_module
from typing import Dict, Iterable, Optional, Tuple, Union
from unittest.mock import patch

from cairo_addons.vm import Relocatable
from starkware.cairo.common.dict import DictTracker
from starkware.cairo.lang.compiler.program import CairoHint

from ethereum.cancun.vm.instructions import Ops
from tests.utils.args_gen import to_cairo_type
from tests.utils.helpers import flatten

MaybeRelocatable = Union[int, Relocatable]


def debug_info(program):
    def _debug_info(pc):
        print(
            program.debug_info.instruction_locations.get(
                pc.offset
            ).inst.to_string_with_content("")
        )

    return _debug_info


def get_op(value: int) -> Ops:
    """Get an Ops enum by its opcode value."""
    try:
        return Ops._value2member_map_[value]
    except KeyError:
        raise ValueError(f"Invalid opcode: {hex(value)}")


def gen_arg_pydantic(
    dict_manager, segments, arg, apply_modulo_to_args=True
) -> Union[MaybeRelocatable, Tuple[MaybeRelocatable, MaybeRelocatable]]:
    """
    To be removed once all models are removed in favor of eels types.
    """
    if isinstance(arg, Dict):
        dict_ptr = segments.add()
        assert dict_ptr.segment_index not in dict_manager.trackers

        data = {
            k: gen_arg_pydantic(dict_manager, segments, v, apply_modulo_to_args)
            for k, v in arg.items()
        }
        if isinstance(arg, defaultdict):
            data = defaultdict(arg.default_factory, data)

        # This is required for tests where we read data from DictAccess segments while no dict method has been used.
        # Equivalent to doing an initial dict_read of all keys.
        initial_data = flatten([(k, v, v) for k, v in data.items()])
        segments.load_data(dict_ptr, initial_data)
        current_ptr = dict_ptr + len(initial_data)
        dict_manager.trackers[dict_ptr.segment_index] = DictTracker(
            data=data, current_ptr=current_ptr
        )

        return dict_ptr, current_ptr

    if isinstance(arg, Iterable):
        base = segments.add()
        arg = flatten(
            [
                gen_arg_pydantic(dict_manager, segments, x, apply_modulo_to_args)
                for x in arg
            ]
        )
        segments.load_data(base, arg)
        return base

    if is_dataclass(arg):
        return gen_arg_pydantic(
            dict_manager, segments, asdict(arg).values(), apply_modulo_to_args
        )

    if apply_modulo_to_args and isinstance(arg, int):
        return arg % segments.prime

    return arg


@contextmanager
def patch_hint(program, hint: str, new_hint: str, scope: Optional[str] = None):
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

    # Determine if we're dealing with nondet hints
    orig_nondet_arg = get_nondet_arg(hint)
    new_nondet_arg = get_nondet_arg(new_hint)

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
                if hint_.code.strip() == hint.strip():
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

    with patch.object(program, "hints", new=patched_hints):
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


def oracle(program, serde, main_path, gen_arg):

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

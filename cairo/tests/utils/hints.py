from collections import defaultdict
from dataclasses import asdict, is_dataclass
from typing import Dict, Iterable, Tuple, Union

from starkware.cairo.common.dict import DictTracker

from cairo_addons.vm import Relocatable
from ethereum.cancun.vm.instructions import Ops
from tests.utils.helpers import flatten

MaybeRelocatable = Union[int, Relocatable]


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

from collections import defaultdict
from contextlib import contextmanager
from dataclasses import asdict, is_dataclass
from typing import Dict, Iterable, Tuple, Union
from unittest.mock import patch

from starkware.cairo.common.dict import DictTracker
from starkware.cairo.lang.compiler.program import CairoHint
from starkware.cairo.lang.vm.relocatable import MaybeRelocatable

from tests.utils.helpers import flatten


def gen_arg(
    dict_manager, segments, arg, apply_modulo_to_args=True
) -> Union[MaybeRelocatable, Tuple[MaybeRelocatable, MaybeRelocatable]]:
    """
    Updated from starkware.cairo.lang.vm.memory_segments.py to handle dicts.
    """
    if isinstance(arg, Dict):
        base = segments.add()
        assert base.segment_index not in dict_manager.trackers

        data = {
            k: gen_arg(dict_manager, segments, v, apply_modulo_to_args)
            for k, v in arg.items()
        }
        if isinstance(arg, defaultdict):
            data = defaultdict(arg.default_factory, data)

        dict_manager.trackers[base.segment_index] = DictTracker(
            data=data, current_ptr=base
        )

        # In case of a dict, it's assumed that the struct **always** have consecutive dict_start, dict_ptr
        # fields.
        return base, base

    if isinstance(arg, Iterable):
        base = segments.add()
        arg = flatten(
            [gen_arg(dict_manager, segments, x, apply_modulo_to_args) for x in arg]
        )
        segments.load_data(base, arg)
        return base

    if is_dataclass(arg):
        return gen_arg(
            dict_manager, segments, asdict(arg).values(), apply_modulo_to_args
        )

    if apply_modulo_to_args and isinstance(arg, int):
        return arg % segments.prime

    return arg


dict_manager = """
if '__dict_manager' not in globals():
    from starkware.cairo.common.dict import DictManager
    __dict_manager = DictManager()
"""

block = f"""
{dict_manager}
from tests.utils.hints import gen_arg

ids.block = gen_arg(__dict_manager, segments, program_input["block"])
"""

account = f"""
{dict_manager}
from tests.utils.hints import gen_arg

ids.account = gen_arg(__dict_manager, segments, program_input["account"])
"""

state = f"""
{dict_manager}
from tests.utils.hints import gen_arg

ids.state = gen_arg(__dict_manager, segments, program_input["state"])
"""

chain_id = """
ids.chain_id = 1
"""

dict_copy = """
from starkware.cairo.common.dict import DictTracker

data = __dict_manager.trackers[ids.dict_start.address_.segment_index].data.copy()
__dict_manager.trackers[ids.new_start.address_.segment_index] = DictTracker(
    data=data,
    current_ptr=ids.new_end.address_,
)
"""

dict_squash = """
data = __dict_manager.get_dict(ids.dict_accesses_end).copy()
base = segments.add()
assert base.segment_index not in __dict_manager.trackers
__dict_manager.trackers[base.segment_index] = DictTracker(
    data=data, current_ptr=base
)
memory[ap] = base
"""

hints = {
    "dict_manager": dict_manager,
    "block": block,
    "account": account,
    "state": state,
    "chain_id": chain_id,
    "dict_copy": dict_copy,
    "dict_squash": dict_squash,
}


def implement_hints(program):
    return {
        k: [
            (
                CairoHint(
                    accessible_scopes=hint_.accessible_scopes,
                    flow_tracking_data=hint_.flow_tracking_data,
                    code=hints.get(hint_.code, hint_.code),
                )
            )
            for hint_ in v
        ]
        for k, v in program.hints.items()
    }


@contextmanager
def patch_hint(program, hint, new_hint):
    patched_hints = {
        k: [
            (
                hint_
                if hint_.code != hint
                else CairoHint(
                    accessible_scopes=hint_.accessible_scopes,
                    flow_tracking_data=hint_.flow_tracking_data,
                    code=new_hint,
                )
            )
            for hint_ in v
        ]
        for k, v in program.hints.items()
    }
    if patched_hints == program.hints:
        raise ValueError(f"Hint\n\n{hint}\n\nnot found in program hints.")
    with patch.object(program, "hints", new=patched_hints):
        yield

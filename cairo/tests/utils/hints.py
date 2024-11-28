from collections import defaultdict
from contextlib import contextmanager
from dataclasses import asdict, is_dataclass
from importlib import import_module
from typing import Dict, Iterable, Optional, Tuple, Union
from unittest.mock import patch

from starkware.cairo.common.dict import DictTracker
from starkware.cairo.lang.compiler.program import CairoHint
from starkware.cairo.lang.vm.relocatable import MaybeRelocatable

from ethereum.cancun.vm.instructions import Ops
from tests.utils.args_gen import to_cairo_type
from tests.utils.constants import CHAIN_ID
from tests.utils.helpers import flatten


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
        base = segments.add()
        assert base.segment_index not in dict_manager.trackers

        data = {
            k: gen_arg_pydantic(dict_manager, segments, v, apply_modulo_to_args)
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


dict_manager = """
if '__dict_manager' not in globals():
    from starkware.cairo.common.dict import DictManager
    __dict_manager = DictManager()
"""

block = f"""
{dict_manager}
from tests.utils.hints import gen_arg_pydantic

ids.block = gen_arg_pydantic(__dict_manager, segments, program_input["block"])
"""

block_hashes = """
import random

ids.block_hashes = segments.gen_arg([random.randint(0, 2**128 - 1) for _ in range(256 * 2)])
"""

account = f"""
{dict_manager}
from tests.utils.hints import gen_arg_pydantic

ids.account = gen_arg_pydantic(__dict_manager, segments, program_input["account"])
"""

state = f"""
{dict_manager}
from tests.utils.hints import gen_arg_pydantic

ids.state = gen_arg_pydantic(__dict_manager, segments, program_input["state"])
"""

chain_id = f"""
ids.chain_id = {CHAIN_ID}
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
from starkware.cairo.common.dict import DictTracker

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
    "block_hashes": block_hashes,
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

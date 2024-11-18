from collections import defaultdict
from contextlib import contextmanager
from dataclasses import asdict, fields, is_dataclass
from functools import partial
from typing import Dict, Iterable, Tuple, Union, get_args, get_origin
from unittest.mock import patch

from starkware.cairo.common.dict import DictTracker
from starkware.cairo.lang.compiler.program import CairoHint
from starkware.cairo.lang.vm.relocatable import MaybeRelocatable

from ethereum.base_types import U256, Bytes, Bytes0, Bytes8, Bytes20, Bytes32, Bytes256
from ethereum.cancun.blocks import Header, Log, Withdrawal
from ethereum.cancun.transactions import Transaction
from ethereum.crypto.hash import Hash32
from src.utils.uint256 import int_to_uint256
from tests.utils.helpers import flatten


def debug_info(program):
    def _debug_info(pc):
        print(
            program.debug_info.instruction_locations.get(
                pc.offset
            ).inst.to_string_with_content("")
        )

    return _debug_info


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


def gen_arg(dict_manager, segments):
    return partial(_gen_arg, dict_manager, segments)


def _gen_arg(
    dict_manager, segments, arg, apply_modulo_to_args=True
) -> Union[MaybeRelocatable, Tuple[MaybeRelocatable, MaybeRelocatable]]:
    """
    Updated from starkware.cairo.lang.vm.memory_segments.py to handle dicts.
    """

    # Base types
    if isinstance(arg, U256):
        return _gen_arg(
            dict_manager,
            segments,
            int_to_uint256(int(arg)),
            apply_modulo_to_args,
        )

    if isinstance(arg, Bytes0) or isinstance(arg, Bytes8) or isinstance(arg, Bytes20):
        return _gen_arg(
            dict_manager, segments, int.from_bytes(arg, "big"), apply_modulo_to_args
        )

    if isinstance(arg, Hash32) or isinstance(arg, Bytes32):
        return _gen_arg(
            dict_manager,
            segments,
            int_to_uint256(int.from_bytes(arg, "big")),
            apply_modulo_to_args,
        )

    if isinstance(arg, Bytes256):
        return _gen_arg(
            dict_manager,
            segments,
            (int.from_bytes(arg[i : i + 16], "big") for i in range(0, len(arg), 16)),
            apply_modulo_to_args,
        )

    if isinstance(arg, Bytes):
        return _gen_arg(
            dict_manager, segments, (list(arg), len(arg)), apply_modulo_to_args
        )

    if isinstance(arg, Transaction):
        return _gen_arg(
            dict_manager,
            segments,
            [
                (
                    [
                        (
                            getattr(arg, field.name)
                            if not get_origin(field.type) == Union
                            else [
                                (
                                    [getattr(arg, field.name)]
                                    if isinstance(getattr(arg, field.name), t_arg)
                                    else 0
                                )
                                for t_arg in get_args(field.type)
                            ]
                        )
                        for field in fields(arg)
                    ]
                    if isinstance(arg, t)
                    else 0
                )
                for t in get_args(Transaction)
            ],
            apply_modulo_to_args,
        )

    # Empty tuples will match also match this case.
    if isinstance(arg, tuple) and (
        all(isinstance(x, Log) for x in arg)
        or all(isinstance(x, Hash32) for x in arg)
        or all(isinstance(x, Bytes32) for x in arg)
        or all(isinstance(x, Bytes) for x in arg)
        or all(isinstance(x, Withdrawal) for x in arg)
        or all(isinstance(x, Header) for x in arg)
    ):
        return _gen_arg(
            dict_manager,
            segments,
            (
                (
                    _gen_arg(dict_manager, segments, x, apply_modulo_to_args)
                    for x in arg
                ),
                len(arg),
            ),
            apply_modulo_to_args,
        )

    if isinstance(arg, bool):
        return int(arg)

    if isinstance(arg, Dict):
        base = segments.add()
        assert base.segment_index not in dict_manager.trackers

        data = {
            k: _gen_arg(dict_manager, segments, v, apply_modulo_to_args)
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
        arg = [_gen_arg(dict_manager, segments, x, apply_modulo_to_args) for x in arg]
        segments.load_data(base, arg)
        return base

    if is_dataclass(arg) and not isinstance(arg, MaybeRelocatable):
        return _gen_arg(
            dict_manager,
            segments,
            # Not using astuple to keep the typing of each field.
            [getattr(arg, field.name) for field in fields(arg)],
            apply_modulo_to_args,
        )

    if apply_modulo_to_args and isinstance(arg, int):
        return int(arg) % segments.prime

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

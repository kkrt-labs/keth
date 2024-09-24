from collections import defaultdict
from contextlib import contextmanager
from unittest.mock import patch

from starkware.cairo.common.dict import DictTracker
from starkware.cairo.lang.compiler.program import CairoHint


def debug_info(program):
    def _debug_info(pc):
        print(
            program.debug_info.instruction_locations.get(
                pc.offset
            ).inst.to_string_with_content("")
        )

    return _debug_info


def new_default_dict(
    dict_manager, segments, default_value, initial_dict, temp_segment: bool = False
):
    """
    Create a new Cairo default dictionary.
    """
    base = segments.add_temp_segment() if temp_segment else segments.add()
    assert base.segment_index not in dict_manager.trackers
    dict_manager.trackers[base.segment_index] = DictTracker(
        data=defaultdict(lambda: default_value, initial_dict),
        current_ptr=base,
    )
    return base


block_info = """
ids.block_info.coinbase = 1
ids.block_info.timestamp = 2
ids.block_info.number = 3
ids.block_info.prev_randao.low = 4
ids.block_info.prev_randao.high = 5
ids.block_info.gas_limit = 6
ids.block_info.chain_id = 7
ids.block_info.base_fee = 8
"""


transaction_hash = """
"""

hints = {"block_info": block_info, "transaction_hash": transaction_hash}


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

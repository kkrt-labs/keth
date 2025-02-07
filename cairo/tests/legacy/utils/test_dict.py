from collections import defaultdict
from typing import List, Mapping, Tuple

from ethereum.cancun.fork_types import Address
from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U256, Uint
from hypothesis import given
from hypothesis import strategies as st
from starkware.cairo.common.dict import DictManager
from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.relocatable import RelocatableValue
from starkware.cairo.lang.vm.vm_consts import VmConsts

from cairo_addons.hints.decorator import register_hint
from tests.utils.strategies import felt


# Hints for tests
@register_hint
def dict_update_test_hint(
    dict_manager: DictManager,
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
    ap: RelocatableValue,
):
    input_dict_len = (
        ids.input_mapping.value.dict_ptr.address_
        - ids.input_mapping.value.dict_ptr_start.address_
    ) // 3
    current_dict_addr = ids.new_dict_ptr.address_
    for i in range(input_dict_len):
        memory[current_dict_addr] = ids.input_mapping.value.dict_ptr_start[i].key.value
        memory[current_dict_addr + 1] = ids.input_mapping.value.dict_ptr_start[
            i
        ].prev_value.value
        memory[current_dict_addr + 2] = (
            ids.input_mapping.value.dict_ptr_start[i].new_value.value + 1
        )
        current_dict_addr += ids.UintDictAccess.SIZE

    ids.modified_dict_end = current_dict_addr
    dict_tracker = dict_manager.get_tracker(ids.new_dict_ptr)
    dict_tracker.current_ptr = ids.modified_dict_end.address_


@register_hint
def prev_values_test_hint(
    dict_manager: DictManager,
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
    ap: RelocatableValue,
    program_input: dict,
):
    flattened_entries = [
        item for sublist in program_input["dict_entries"] for item in sublist
    ]
    segments.write_arg(ids.dict_ptr_start.address_, flattened_entries)
    ids.dict_ptr_stop = ids.dict_ptr_start.address_ + 3 * len(
        program_input["dict_entries"]
    )


@given(dict_entries=st.lists(st.tuples(felt, felt, felt)))
def test_prev_values(cairo_run_py, dict_entries: List[Tuple[int, int, int]]):
    prev_values = cairo_run_py("test_prev_values", dict_entries=dict_entries)

    assert all(
        prev_values[i * 3 : i * 3 + 3] == [key, prev, prev]
        for i, (key, prev, _) in enumerate(dict_entries)
    )


@given(parent_dict=..., drop=...)
def test_dict_update(cairo_run_py, parent_dict: Mapping[Uint, Uint], drop: bool):
    finalized_dict = cairo_run_py("test_dict_update", parent_dict, drop)

    for original_value, new_value in zip(parent_dict.values(), finalized_dict.values()):
        assert new_value == original_value + Uint(1 - int(drop))


@st.composite
def dict_with_prefix(draw):
    # Draw a single value for the prefix
    prefix = draw(st.from_type(Address))

    # Generate a dictionary where each key has 50% chance of having the prefix
    dict_entries = draw(
        st.dictionaries(
            keys=st.tuples(
                st.one_of(
                    st.just(prefix),  # 50% chance of using the prefix
                    st.from_type(Address),  # 50% chance of random bytes20
                ),
                st.from_type(Bytes32),
            ),
            values=st.from_type(U256),
            min_size=1,
            max_size=50,
        )
    )

    return dict_entries, prefix


@given(dict_with_prefix=dict_with_prefix())
def test_get_keys_for_address_prefix(cairo_run, dict_with_prefix):
    dict_entries: Mapping[Tuple[Address, Bytes32], U256] = dict_with_prefix[0]
    prefix: Address = dict_with_prefix[1]
    keys = cairo_run("test_get_keys_for_address_prefix", prefix, dict_entries)
    keys = [keys] if not isinstance(keys, list) else keys
    assert set(tuple(k) for k in keys) == {
        key for key in dict_entries.keys() if key[0] == prefix
    }


@given(src_dict=..., dst_dict=...)
def test_squash_and_update(
    cairo_run,
    src_dict: Mapping[Tuple[Address, Bytes32], U256],
    dst_dict: Mapping[Tuple[Address, Bytes32], U256],
):
    new_dst_dict = cairo_run(
        "test_squash_and_update",
        defaultdict(lambda: U256(0), src_dict),
        defaultdict(lambda: U256(0), dst_dict),
    )
    dst_dict.update(src_dict)
    assert new_dst_dict == dst_dict

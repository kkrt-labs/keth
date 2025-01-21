from typing import List, Mapping, Tuple

import pytest
from cairo_addons.hints.decorator import register_hint
from ethereum_types.numeric import Uint
from hypothesis import given
from hypothesis import strategies as st
from starkware.cairo.common.dict import DictManager
from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.relocatable import RelocatableValue
from starkware.cairo.lang.vm.vm_consts import VmConsts

from tests.utils.strategies import felt

pytestmark = pytest.mark.python_vm


# Hints for tests
@register_hint
def hashdict_finalize_test_hint(
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


@given(original_mapping=..., merge=...)
def test_hashdict_finalize(
    cairo_run_py, original_mapping: Mapping[Uint, Uint], merge: bool
):
    finalized_dict = cairo_run_py("test_hashdict_finalize", original_mapping, merge)

    for original_value, new_value in zip(
        original_mapping.values(), finalized_dict.values()
    ):
        assert new_value == original_value + Uint(int(merge))

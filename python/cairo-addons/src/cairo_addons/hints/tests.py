from cairo_addons.hints.decorator import register_hint
from starkware.cairo.common.dict import DictManager
from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.relocatable import RelocatableValue
from starkware.cairo.lang.vm.vm_consts import VmConsts


# Hints for tests
@register_hint
def test_hashdict_finalize(
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
def test_prev_values(
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

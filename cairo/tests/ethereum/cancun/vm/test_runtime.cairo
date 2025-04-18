%builtins range_check

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.dict_access import DictAccess
from ethereum_types.bytes import Bytes, BytesStruct
from ethereum.cancun.vm.runtime import (
    get_valid_jump_destinations,
    finalize_jumpdests,
    assert_valid_jumpdest,
)
from legacy.utils.dict import dict_squash

func test__get_valid_jump_destinations{range_check_ptr}(code: Bytes) -> felt* {
    alloc_locals;

    let valid_jumpdests = get_valid_jump_destinations(code);
    let valid_jumpdests_ptr = valid_jumpdests.value.dict_ptr;

    let (output) = alloc();
    %{ segments.load_data(ids.output, [k[0] for k in dict_manager.get_dict(ids.valid_jumpdests_ptr).keys()]) %}

    return output;
}

func test__finalize_jumpdests{range_check_ptr}(bytecode: Bytes) {
    alloc_locals;

    tempvar valid_jumpdests_start: DictAccess*;
    tempvar valid_jumpdests: DictAccess*;
    %{
        from starkware.cairo.common.dict import DictTracker
        from cairo_addons.rust_bindings.vm import DictTracker as RustDictTracker, DictManager as RustDictManager
        from tests.utils.helpers import flatten
        from ethereum.cancun.vm.runtime import get_valid_jump_destinations

        bytecode = [memory[ids.bytecode.value.data + i] for i in range(0, ids.bytecode.value.len)]
        data = {k: 1 for k in get_valid_jump_destinations(bytecode)}

        base = segments.add()
        segments.load_data(
            base,
            flatten([[int(k), 1, 1] for k in data.keys()])
        )
        if isinstance(dict_manager, RustDictManager):
            dict_manager.trackers[base.segment_index] = RustDictTracker(
                data=data,
                current_ptr=(base + len(data) * 3),
            )
        else:
            dict_manager.trackers[base.segment_index] = DictTracker(
                data=data,
                current_ptr=(base + len(data) * 3),
            )
        ids.valid_jumpdests_start = base
        ids.valid_jumpdests = base + len(data) * 3
    %}

    let (sorted_keys_start, sorted_keys_end) = dict_squash(valid_jumpdests_start, valid_jumpdests);

    finalize_jumpdests(0, sorted_keys_start, sorted_keys_end, bytecode);

    return ();
}

func test__assert_valid_jumpdest{range_check_ptr}(bytecode: Bytes) {
    alloc_locals;
    tempvar valid_jumpdest: DictAccess*;
    %{
        ids.valid_jumpdest = segments.add()
        segments.load_data(ids.valid_jumpdest.address_, program_input["valid_jumpdest"])
    %}
    assert_valid_jumpdest(0, bytecode, valid_jumpdest);
    return ();
}

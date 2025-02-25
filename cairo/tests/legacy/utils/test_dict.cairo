from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.default_dict import default_dict_new, default_dict_finalize
from starkware.cairo.common.dict import dict_write, dict_read
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import Uint256
from ethereum_types.numeric import Uint
from ethereum.cancun.fork_types import Address, TupleAddressBytes32
from ethereum.cancun.state import (
    MappingTupleAddressBytes32U256,
    MappingTupleAddressBytes32U256Struct,
    TupleAddressBytes32U256DictAccess,
    ListTupleAddressBytes32,
    ListTupleAddressBytes32Struct,
)
from legacy.utils.dict import (
    prev_values,
    dict_update,
    get_keys_for_address_prefix,
    squash_and_update,
    dict_squash,
)

func test_prev_values{range_check_ptr}() -> (prev_values_start_ptr: felt*) {
    alloc_locals;
    let (local dict_ptr_start: DictAccess*) = alloc();
    local dict_ptr_stop: DictAccess*;
    %{ prev_values_test_hint %}

    let (prev_values_start, prev_values_stop) = prev_values(dict_ptr_start, dict_ptr_stop);

    return (prev_values_start_ptr=cast(prev_values_start, felt*));
}

// For testing purposes.
struct UintDictAccess {
    key: Uint,
    prev_value: Uint,
    new_value: Uint,
}

struct MappingUintUint {
    value: MappingUintUintStruct*,
}

struct MappingUintUintStruct {
    dict_ptr_start: UintDictAccess*,
    dict_ptr: UintDictAccess*,
    parent_dict: MappingUintUintStruct*,
}

func test_dict_update{range_check_ptr}(
    input_mapping: MappingUintUint, drop: felt
) -> MappingUintUint {
    alloc_locals;

    local new_dict_ptr: UintDictAccess*;
    let modified_dict_start = new_dict_ptr;
    let parent_dict_end = input_mapping.value.dict_ptr;
    %{ copy_tracker_to_new_ptr %}

    tempvar modified_dict_end: UintDictAccess*;
    %{ dict_update_test_hint %}
    let (finalized_dict_start, finalized_dict_end) = dict_update(
        cast(modified_dict_start, DictAccess*),
        cast(modified_dict_end, DictAccess*),
        cast(input_mapping.value.dict_ptr_start, DictAccess*),
        cast(input_mapping.value.dict_ptr, DictAccess*),
        drop,
    );

    tempvar result = MappingUintUint(
        new MappingUintUintStruct(
            cast(finalized_dict_start, UintDictAccess*),
            cast(finalized_dict_end, UintDictAccess*),
            input_mapping.value.parent_dict,
        ),
    );
    return result;
}

func test_get_keys_for_address_prefix{range_check_ptr}(
    prefix_: Address, dict_entries: MappingTupleAddressBytes32U256
) -> ListTupleAddressBytes32 {
    alloc_locals;
    let prefix_len = 1;
    let (prefix: felt*) = alloc();
    assert [prefix] = prefix_.value;
    let dict_ptr = cast(dict_entries.value.dict_ptr, DictAccess*);
    let res = get_keys_for_address_prefix{dict_ptr=dict_ptr}(prefix_len, prefix);
    return res;
}

func test_squash_and_update{range_check_ptr}(
    src_dict: MappingTupleAddressBytes32U256, dst_dict: MappingTupleAddressBytes32U256
) -> MappingTupleAddressBytes32U256 {
    alloc_locals;

    let src_start = src_dict.value.dict_ptr_start;
    let src_end = src_dict.value.dict_ptr;
    let dst = dst_dict.value.dict_ptr;
    let new_dst_end = squash_and_update(
        cast(src_start, DictAccess*), cast(src_end, DictAccess*), cast(dst, DictAccess*)
    );

    // Squash the dict another time to ensure that the update was done correctly
    let (final_start, final_end) = dict_squash(
        cast(dst_dict.value.dict_ptr_start, DictAccess*), new_dst_end
    );

    tempvar new_dst_dict = MappingTupleAddressBytes32U256(
        new MappingTupleAddressBytes32U256Struct(
            dict_ptr_start=cast(final_start, TupleAddressBytes32U256DictAccess*),
            dict_ptr=cast(final_end, TupleAddressBytes32U256DictAccess*),
            parent_dict=dst_dict.value.parent_dict,
        ),
    );
    return new_dst_dict;
}

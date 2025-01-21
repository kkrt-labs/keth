from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.default_dict import default_dict_new, default_dict_finalize
from starkware.cairo.common.dict import dict_write, dict_read
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import Uint256
from ethereum_types.numeric import Uint
from src.utils.dict import prev_values, dict_update

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
    original_mapping: MappingUintUintStruct*,
}

func test_dict_update{range_check_ptr}(
    input_mapping: MappingUintUint, drop: felt
) -> MappingUintUint {
    alloc_locals;

    local new_dict_ptr: UintDictAccess*;
    let modified_dict_start = new_dict_ptr;
    let original_mapping = input_mapping.value;
    %{ copy_dict_segment %}

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
            input_mapping.value.original_mapping,
        ),
    );
    return result;
}

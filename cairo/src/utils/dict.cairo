from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.default_dict import default_dict_new
from starkware.cairo.common.dict import dict_write, dict_squash
from starkware.cairo.common.math_cmp import is_not_zero
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.memcpy import memcpy

from src.utils.maths import unsigned_div_rem

func dict_keys{range_check_ptr}(dict_start: DictAccess*, dict_end: DictAccess*) -> (
    keys_len: felt, keys: felt*
) {
    alloc_locals;
    let (local keys_start: felt*) = alloc();
    let dict_len = dict_end - dict_start;
    let (local keys_len, _) = unsigned_div_rem(dict_len, DictAccess.SIZE);
    local range_check_ptr = range_check_ptr;

    if (dict_len == 0) {
        return (keys_len, keys_start);
    }

    tempvar keys = keys_start;
    tempvar len = keys_len;
    tempvar dict = dict_start;

    loop:
    let keys = cast([ap - 3], felt*);
    let len = [ap - 2];
    let dict = cast([ap - 1], DictAccess*);

    assert [keys] = dict.key;
    tempvar keys = keys + 1;
    tempvar len = len - 1;
    tempvar dict = dict + DictAccess.SIZE;

    static_assert keys == [ap - 3];
    static_assert len == [ap - 2];
    static_assert dict == [ap - 1];

    jmp loop if len != 0;

    return (keys_len, keys_start);
}

func dict_values{range_check_ptr}(dict_start: DictAccess*, dict_end: DictAccess*) -> (
    values_len: felt, values: Uint256*
) {
    alloc_locals;
    let (local values: Uint256*) = alloc();
    let dict_len = dict_end - dict_start;
    let (local values_len, _) = unsigned_div_rem(dict_len, DictAccess.SIZE);
    local range_check_ptr = range_check_ptr;

    if (dict_len == 0) {
        return (values_len, values);
    }

    tempvar index = 0;
    tempvar len = values_len;
    tempvar dict = dict_start;

    loop:
    let index = [ap - 3];
    let len = [ap - 2];
    let dict = cast([ap - 1], DictAccess*);

    let pointer = cast(dict.new_value, Uint256*);
    assert values[index] = pointer[0];

    tempvar index = index + 1;
    tempvar len = len - 1;
    tempvar dict = dict + DictAccess.SIZE;

    static_assert index == [ap - 3];
    static_assert len == [ap - 2];
    static_assert dict == [ap - 1];

    jmp loop if len != 0;

    return (values_len, values);
}

func default_dict_copy{range_check_ptr}(start: DictAccess*, end: DictAccess*) -> (
    DictAccess*, DictAccess*
) {
    alloc_locals;
    let (local new_start: DictAccess*) = alloc();
    let new_end = new_start + (end - start);
    memcpy(new_start, start, end - start);
    %{ dict_copy %}
    return (new_start, new_end);
}

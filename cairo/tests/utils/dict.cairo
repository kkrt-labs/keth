from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.dict_access import DictAccess
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

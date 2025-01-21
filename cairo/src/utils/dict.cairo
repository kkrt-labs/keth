from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.builtin_poseidon.poseidon import poseidon_hash, poseidon_hash_many
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.bool import FALSE
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.squash_dict import squash_dict
from starkware.cairo.common.uint256 import Uint256
from ethereum_types.numeric import U256, U256Struct
from ethereum_types.bytes import Bytes32
from ethereum.utils.numeric import U256__eq__, is_not_zero
from ethereum.cancun.fork_types import Address, Account, AccountStruct, Account__eq__

from src.utils.maths import unsigned_div_rem

// @ notice: Creates a new, empty dict, does not require an `initial_dict` argument.
func dict_new_empty() -> (res: DictAccess*) {
    %{ dict_new_empty %}
    ap += 1;
    return (res=cast([ap - 1], DictAccess*));
}

func dict_copy{range_check_ptr}(dict_start: DictAccess*, dict_end: DictAccess*) -> (
    DictAccess*, DictAccess*
) {
    alloc_locals;
    let (local new_start: DictAccess*) = alloc();
    tempvar new_end = new_start + (dict_end - dict_start);
    memcpy(new_start, dict_start, dict_end - dict_start);
    // Register the segment as a dict in the DictManager.
    %{ dict_copy %}
    return (new_start, new_end);
}

// @dev Copied from the standard library with an updated dict_new() implementation.
func dict_squash{range_check_ptr}(
    dict_accesses_start: DictAccess*, dict_accesses_end: DictAccess*
) -> (squashed_dict_start: DictAccess*, squashed_dict_end: DictAccess*) {
    alloc_locals;

    %{ dict_squash %}
    ap += 1;
    let squashed_dict_start = cast([ap - 1], DictAccess*);

    let (squashed_dict_end) = squash_dict(
        dict_accesses=dict_accesses_start,
        dict_accesses_end=dict_accesses_end,
        squashed_dict=squashed_dict_start,
    );

    %{
        # Update the DictTracker's current_ptr to point to the end of the squashed dict.
        __dict_manager.get_tracker(ids.squashed_dict_start).current_ptr = \
            ids.squashed_dict_end.address_
    %}
    return (squashed_dict_start=squashed_dict_start, squashed_dict_end=squashed_dict_end);
}

// A wrapper around dict_read that hashes the key before accessing the dictionary if the key
// does not fit in a felt.
// @param key_len: The number of felt values used to represent the key.
// @param key: The key to access the dictionary.
// TODO: write the associated squash function.
func hashdict_read{poseidon_ptr: PoseidonBuiltin*, dict_ptr: DictAccess*}(
    key_len: felt, key: felt*
) -> (value: felt) {
    alloc_locals;
    local felt_key;
    if (key_len == 1) {
        assert felt_key = key[0];
        tempvar poseidon_ptr = poseidon_ptr;
    } else {
        let (felt_key_) = poseidon_hash_many(key_len, key);
        assert felt_key = felt_key_;
        tempvar poseidon_ptr = poseidon_ptr;
    }

    local value;
    %{ hashdict_read %}
    dict_ptr.key = felt_key;
    dict_ptr.prev_value = value;
    dict_ptr.new_value = value;
    let dict_ptr = dict_ptr + DictAccess.SIZE;
    return (value=value);
}

// A wrapper around dict_read that hashes the key before accessing the dictionary if the key
// does not fit in a felt.
// @dev This version returns 0, if the key is not found and the dict is NOT a defaultdict.
// @param key_len: The readnumber of felt values used to represent the key.
// @param key: The key to access the dictionary.
// TODO: write the associated squash function.
func hashdict_get{poseidon_ptr: PoseidonBuiltin*, dict_ptr: DictAccess*}(
    key_len: felt, key: felt*
) -> (value: felt) {
    alloc_locals;
    local felt_key;
    if (key_len == 1) {
        assert felt_key = key[0];
        tempvar poseidon_ptr = poseidon_ptr;
    } else {
        let (felt_key_) = poseidon_hash_many(key_len, key);
        assert felt_key = felt_key_;
        tempvar poseidon_ptr = poseidon_ptr;
    }

    local value;
    %{ hashdict_get %}
    dict_ptr.key = felt_key;
    dict_ptr.prev_value = value;
    dict_ptr.new_value = value;
    let dict_ptr = dict_ptr + DictAccess.SIZE;
    return (value=value);
}

// A wrapper around dict_write that hashes the key before accessing the dictionary if the key
// does not fit in a felt.
// @param key_len: The number of felt values used to represent the key.
// @param key: The key to access the dictionary.
// @param new_value: The value to write to the dictionary.
func hashdict_write{poseidon_ptr: PoseidonBuiltin*, dict_ptr: DictAccess*}(
    key_len: felt, key: felt*, new_value: felt
) {
    alloc_locals;
    local felt_key;
    if (key_len == 1) {
        assert felt_key = key[0];
        tempvar poseidon_ptr = poseidon_ptr;
    } else {
        let (felt_key_) = poseidon_hash_many(key_len, key);
        assert felt_key = felt_key_;
        tempvar poseidon_ptr = poseidon_ptr;
    }
    %{ hashdict_write %}
    dict_ptr.key = felt_key;
    dict_ptr.new_value = new_value;
    let dict_ptr = dict_ptr + DictAccess.SIZE;
    return ();
}

func hashdict_finalize{range_check_ptr}(
    dict_ptr_start: DictAccess*,
    dict_ptr: DictAccess*,
    original_mapping_start: DictAccess*,
    original_mapping_end: DictAccess*,
    merge: felt,
) -> (DictAccess*, DictAccess*) {
    alloc_locals;

    if (merge == FALSE) {
        let (squashed_dict_start: DictAccess*) = alloc();
        let (squashed_dict_end) = squash_dict(dict_ptr_start, dict_ptr, squashed_dict_start);
        let (prev_values_start, prev_values_end) = prev_values(
            squashed_dict_start, squashed_dict_end
        );
    } else {
        tempvar range_check_ptr = range_check_ptr;
        tempvar dict_ptr_start = dict_ptr_start;
        tempvar dict_ptr = dict_ptr;
    }
    let range_check_ptr = [ap - 3];
    let dict_ptr_start = cast([ap - 2], DictAccess*);
    let dict_ptr = cast([ap - 1], DictAccess*);

    if (cast(original_mapping_end, felt) == 0) {
        // No parent mapping, just return the current dict.
        return (dict_ptr_start, dict_ptr);
    }

    tempvar len = dict_ptr - dict_ptr_start;
    memcpy(original_mapping_end, dict_ptr_start, len);
    let new_original_mapping_end = original_mapping_end + len;
    return (original_mapping_start, new_original_mapping_end);
}

// @notice Given a dict segment (start and end), returns a new dict segment with (key, prev_value, prev_value) for each key.
// @dev Expectes the given dict to be squashed, with one DictAccess instance per key.
// @param dict_ptr_start: The start of the dict segment.
// @param dict_ptr_stop: The end of the dict segment.
// @return prev_values_start: The start of the new dict segment.
// @return prev_values_end: The end of the new dict segment.
func prev_values{range_check_ptr}(dict_ptr_start: DictAccess*, dict_ptr_stop: DictAccess*) -> (
    prev_values_start: DictAccess*, prev_values_end: DictAccess*
) {
    alloc_locals;

    let (local prev_values_start: DictAccess*) = alloc();
    if (dict_ptr_start == dict_ptr_stop) {
        return (prev_values_start, prev_values_start);
    }

    tempvar prev_values = prev_values_start;
    tempvar dict_ptr = dict_ptr_start;
    ap += 4;

    static_assert prev_values == [ap - 6];
    static_assert dict_ptr == [ap - 5];

    loop:
    let prev_values = cast([ap - 6], DictAccess*);
    let dict_ptr = cast([ap - 5], DictAccess*);

    let key = dict_ptr.key;
    let prev_value = dict_ptr.prev_value;

    assert prev_values.key = key;
    assert prev_values.prev_value = prev_value;
    assert prev_values.new_value = prev_value;

    tempvar prev_values = prev_values + DictAccess.SIZE;
    tempvar dict_ptr = dict_ptr + DictAccess.SIZE;
    let is_not_done = is_not_zero(dict_ptr_stop - dict_ptr);

    static_assert prev_values == [ap - 6];
    static_assert dict_ptr == [ap - 5];
    jmp loop if is_not_done != 0;

    return (prev_values_start=prev_values_start, prev_values_end=prev_values);
}

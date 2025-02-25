from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.default_dict import default_dict_finalize_inner
from starkware.cairo.common.builtin_poseidon.poseidon import poseidon_hash, poseidon_hash_many
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.bool import FALSE
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.squash_dict import squash_dict
from starkware.cairo.common.uint256 import Uint256
from cairo_core.comparison import is_zero, is_not_zero
from ethereum.cancun.fork_types import (
    ListTupleAddressBytes32,
    ListTupleAddressBytes32Struct,
    TupleAddressBytes32,
)

// @ notice: Creates a new, empty dict, does not require an `initial_dict` argument.
func dict_new_empty() -> (res: DictAccess*) {
    %{ dict_new_empty %}
    ap += 1;
    return (res=cast([ap - 1], DictAccess*));
}

// Reads a value from the dictionary and returns the result.
// @dev The key is as a tuple of size 1 in the tracker.
func dict_read{dict_ptr: DictAccess*}(key_: felt) -> (value: felt) {
    alloc_locals;
    let (__fp__, _) = get_fp_and_pc();
    let key_len = 1;
    let key = &key_;
    local value;
    %{ hashdict_read %}
    dict_ptr.key = key_;
    dict_ptr.prev_value = value;
    dict_ptr.new_value = value;
    let dict_ptr = dict_ptr + DictAccess.SIZE;
    return (value=value);
}

// Writes a value to the dictionary, overriding the existing value.
// @dev The key is as a tuple of size 1 in the tracker.
func dict_write{dict_ptr: DictAccess*}(key_: felt, new_value: felt) {
    let key_len = 1;
    let key = &key_;
    %{ hashdict_write %}
    dict_ptr.key = key_;
    dict_ptr.new_value = new_value;
    let dict_ptr = dict_ptr + DictAccess.SIZE;
    return ();
}

// @notice Copies a dict segment
// @dev The tracker values of the original segment are copied to the new segment in hints.
// @dev In most cases, prefer using the fork mechanism from "copy_tracker_to_new_ptr" without
// copying the segment data.
func dict_copy{range_check_ptr}(dict_start: DictAccess*, dict_end: DictAccess*) -> (
    DictAccess*, DictAccess*
) {
    alloc_locals;
    let parent_dict_end = dict_end;
    tempvar new_dict_ptr: DictAccess*;
    %{ copy_tracker_to_new_ptr %}
    tempvar new_end = new_dict_ptr + (dict_end - dict_start);
    memcpy(new_dict_ptr, dict_start, dict_end - dict_start);
    // Register the segment as a dict in the DictManager.
    return (new_dict_ptr, new_end);
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

// @dev Copied from the standard library and using the updated dict_squash function.
func default_dict_finalize{range_check_ptr}(
    dict_accesses_start: DictAccess*, dict_accesses_end: DictAccess*, default_value: felt
) -> (squashed_dict_start: DictAccess*, squashed_dict_end: DictAccess*) {
    alloc_locals;
    let (local squashed_dict_start, local squashed_dict_end) = dict_squash(
        dict_accesses_start, dict_accesses_end
    );
    local range_check_ptr = range_check_ptr;

    default_dict_finalize_inner(
        dict_accesses_start=squashed_dict_start,
        n_accesses=(squashed_dict_end - squashed_dict_start) / DictAccess.SIZE,
        default_value=default_value,
    );
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

// @notice Given a dict segment (start, end) and a pointer to another dict segment (parent_dict_start, parent_dict_end),
// updates the original dict segment with the new values from the given dict segment.
// @dev If the drop flag is set to false, the new values are added to the existing values.
// @dev If the drop flag is set to true, the new values are discarded, and only the prev_values are appended to the original dict segment.
// @param drop: If false, the new values are added to the existing values.
// @return new_dict_start: The start of the updated dict segment.
// @return new_dict_end: The end of the updated dict segment.
func dict_update{range_check_ptr}(
    dict_ptr_start: DictAccess*,
    dict_ptr: DictAccess*,
    parent_dict_start: DictAccess*,
    parent_dict_end: DictAccess*,
    drop: felt,
) -> (DictAccess*, DictAccess*) {
    alloc_locals;

    if (drop != FALSE) {
        // No need to merge a dict tracker, because we revert to the previous dict.
        let (squashed_dict_start: DictAccess*) = alloc();
        let (squashed_dict_end) = squash_dict(dict_ptr_start, dict_ptr, squashed_dict_start);
        let (prev_values_start, prev_values_end) = prev_values(
            squashed_dict_start, squashed_dict_end
        );
    } else {
        %{ merge_dict_tracker_with_parent %}
        tempvar range_check_ptr = range_check_ptr;
        tempvar dict_ptr_start = dict_ptr_start;
        tempvar dict_ptr = dict_ptr;
    }
    let range_check_ptr = [ap - 3];
    let dict_ptr_start = cast([ap - 2], DictAccess*);
    let dict_ptr = cast([ap - 1], DictAccess*);

    if (cast(parent_dict_end, felt) == 0) {
        // No parent mapping, just return the current dict.
        return (dict_ptr_start, dict_ptr);
    }

    tempvar len = dict_ptr - dict_ptr_start;
    memcpy(parent_dict_end, dict_ptr_start, len);
    let new_parent_dict_end = parent_dict_end + len;

    let current_tracker_ptr = parent_dict_end;
    let new_tracker_ptr = new_parent_dict_end;
    %{ update_dict_tracker %}
    return (parent_dict_start, new_parent_dict_end);
}

// @notice Given a dict segment (start and end), returns a new dict segment with (key, prev_value, prev_value) for each key.
// @dev Expects the given dict to be squashed, with one DictAccess instance per key, to avoid creating useless entries.
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

// @notice Returns all keys that have a prefix matching the given prefix.
// TODO: this is unsound and soundness should be ensured at squash time.
func get_keys_for_address_prefix{dict_ptr: DictAccess*}(
    prefix_len: felt, prefix: felt*
) -> ListTupleAddressBytes32 {
    alloc_locals;

    local keys_len: felt;
    local keys: TupleAddressBytes32*;
    %{ get_keys_for_address_prefix %}

    // warning: this is unsound as the prover can return any list of keys.

    tempvar res = ListTupleAddressBytes32(new ListTupleAddressBytes32Struct(keys, keys_len));
    return res;
}

// @notice squashes the `src` dict and writes all its values to the `dst` dict.
// @dev If the `dst` dict is not empty, the values are added to the existing values.
// @param src: The source dict to squash.
// @param dst: The end pointer of the destination dict to write the values to.
// @returns The new end pointer of the destination dict
func squash_and_update{range_check_ptr}(
    src_start: DictAccess*, src_end: DictAccess*, dst: DictAccess*
) -> DictAccess* {
    alloc_locals;

    let (squashed_src_start, local squashed_src_end) = dict_squash(src_start, src_end);
    let len = squashed_src_end - squashed_src_start;
    local range_check_ptr = range_check_ptr;

    if (len == 0) {
        return dst;
    }

    // Loop on all keys and write the new_value to the dst dict.
    tempvar squashed_src = squashed_src_start;
    tempvar dst_end = dst;

    loop:
    let squashed_src = cast([ap - 2], DictAccess*);
    let dst_end = cast([ap - 1], DictAccess*);

    let is_done = is_zero(squashed_src_end - squashed_src);
    static_assert dst_end == [ap - 5];
    jmp done if is_done != 0;

    let key = squashed_src.key;
    let new_value = squashed_src.new_value;
    assert dst_end.key = key;
    let dict_ptr_stop = dst;
    tempvar value;
    // Get the prev value from a hint, as it will be verified upon squashing.
    %{ hashdict_read_from_key %}
    assert dst_end.prev_value = value;
    assert dst_end.new_value = new_value;

    tempvar squashed_src = squashed_src + DictAccess.SIZE;
    tempvar dst_end = dst_end + DictAccess.SIZE;
    jmp loop;

    done:
    // Merge
    let dict_ptr = squashed_src_end;
    let parent_dict_end = dst;
    %{ merge_dict_tracker_with_parent %}

    let current_tracker_ptr = dst;
    let new_tracker_ptr = cast([ap - 5], DictAccess*);
    %{ update_dict_tracker %}

    return new_tracker_ptr;
}

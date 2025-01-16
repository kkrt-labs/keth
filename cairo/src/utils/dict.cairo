from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.builtin_poseidon.poseidon import poseidon_hash, poseidon_hash_many
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.squash_dict import squash_dict
from starkware.cairo.common.uint256 import Uint256
from ethereum_types.numeric import U256, U256Struct
from ethereum_types.bytes import Bytes32
from ethereum.utils.numeric import U256__eq__
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

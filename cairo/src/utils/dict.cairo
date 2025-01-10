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
    %{
        dict_tracker = __dict_manager.get_tracker(ids.dict_ptr)
        dict_tracker.current_ptr += ids.DictAccess.SIZE
        preimage = tuple([memory[ids.key + i] for i in range(ids.key_len)])
        # Not using [] here because it will register the value for that key in the tracker.
        ids.value = dict_tracker.data.get(preimage, dict_tracker.data.default_factory())
    %}
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
    %{
        dict_tracker = __dict_manager.get_tracker(ids.dict_ptr)
        dict_tracker.current_ptr += ids.DictAccess.SIZE
        preimage = tuple([memory[ids.key + i] for i in range(ids.key_len)])
        ids.dict_ptr.prev_value = dict_tracker.data[preimage]
        dict_tracker.data[preimage] = ids.new_value
    %}
    dict_ptr.key = felt_key;
    dict_ptr.new_value = new_value;
    let dict_ptr = dict_ptr + DictAccess.SIZE;
    return ();
}

// @notice Assertions on a
// value if that key is present, or writes the new value if the key is not present.
// @param key_len: The number of felt values used to represent the key.
// @param key: The key to access the dictionary.
// @param new_value: The value to write to the dictionary.
func hashdict_delete_if_present_u256{
    poseidon_ptr: PoseidonBuiltin*, dict_ptr_start: DictAccess*, dict_ptr: DictAccess*
}(key_len: felt, key: felt*, value: U256) {
    alloc_locals;
    let (felt_key, last_key_entry_ptr) = hint_last_key_entry_ptr(key_len, key);

    // An entry associated with that key was found: delete it.
    if (last_key_entry_ptr != 0) {
        // See `hashdict_delete_if_present_u256` comments
        let u256_eq = U256__eq__(U256(cast([last_key_entry_ptr].new_value, U256Struct*)), value);
        assert u256_eq.value = 1;

        assert dict_ptr.prev_value = [last_key_entry_ptr].new_value;

        tempvar ptr_zero = cast(0, DictAccess*);
        dict_ptr.new_value = ptr_zero;
        let dict_ptr = dict_ptr + DictAccess.SIZE;
        return ();
    }

    // No entry associated with that key was found: don't do anything.
    tempvar prev_value = dict_ptr.prev_value;
    dict_ptr.new_value = prev_value;
    let dict_ptr = dict_ptr + DictAccess.SIZE;
    return ();
}

func hashdict_delete_if_present_account{
    poseidon_ptr: PoseidonBuiltin*, dict_ptr_start: DictAccess*, dict_ptr: DictAccess*
}(key_len: felt, key: felt*, value: Account) {
    alloc_locals;

    // Note: `key_entry_ptr` is verified to be a ptr to __a__ key entry in the dict segment for that key.
    // but might not be the last one: it needs to be verified.
    let (felt_key, last_key_entry_ptr) = hint_last_key_entry_ptr(key_len, key);

    // An entry associated with that key was found: delete it.
    if (last_key_entry_ptr != 0) {
        // For soundness purposes, we verify that the account value at that key is the same as the one
        // passed in argument.
        // This asserts _now_ that the __value__ of the account at that key is the same as the one passed in argument.
        // AND that the pointer to the account at that key is the same as our prev_value.
        // During squashing, we will verify that all sequential (new_{i-1} = prev_{i}) pointers are the same.

        // 1. Verify that the account provided as value matches the account at that last key.
        tempvar prev_account = Account(cast([last_key_entry_ptr].new_value, AccountStruct*));
        let accounts_eq = Account__eq__(prev_account, value);
        assert accounts_eq.value = 1;

        // 2. Verify that the pointer to the account at that last key is the same as our prev_value (given by the prover).
        assert dict_ptr.prev_value = [last_key_entry_ptr].new_value;

        // 3. Set the new_value to 0 to indicate that the key has been deleted.
        tempvar ptr_zero = cast(0, DictAccess*);
        dict_ptr.new_value = ptr_zero;
        let dict_ptr = dict_ptr + DictAccess.SIZE;

        return ();
    }

    tempvar prev_value = dict_ptr.prev_value;
    assert prev_value = 0;
    dict_ptr.new_value = prev_value;
    let dict_ptr = dict_ptr + DictAccess.SIZE;
    return ();
}

// @notice Returns the felt_key (hashed key if key_len > 1) and the last_key_entry_ptr (pointer to the last
// key entry in the dict segment for that key).
// @dev The "felt_key" is computed in Cairo. The `last_key_entry_ptr` is provided by the prover and is
// asserted to be equal to the `felt_key` for soundness purposes.
// @dev Technically, the prover could be returning a ptr to a key that is not the last one, but simply
// is the correct key. Thus, any function that uses this hint must also add assertions related to their logic.
// @param key_len: The number of felt values used to represent the key.
// @param key: The key to access the dictionary.
func hint_last_key_entry_ptr{
    poseidon_ptr: PoseidonBuiltin*, dict_ptr_start: DictAccess*, dict_ptr: DictAccess*
}(key_len: felt, key: felt*) -> (felt_key: felt, last_key_entry_ptr: DictAccess*) {
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

    // The last key entry in the dict segment for that key
    tempvar last_key_entry_ptr: DictAccess*;
    %{
        from tests.utils.hints import DELETED_KEY_FLAG
        dict_tracker = __dict_manager.get_tracker(ids.dict_ptr)
        segment_size = ids.dict_ptr.address_ - ids.dict_ptr_start.address_
        dict_tracker.current_ptr += ids.DictAccess.SIZE
        preimage = tuple([memory[ids.key + i] for i in range(ids.key_len)])
        if preimage in dict_tracker.data:
            # Deleting the key means writing a special value to the dictionary to represent a deleted value.
            ids.dict_ptr.prev_value = dict_tracker.data[preimage]
            dict_tracker.data[preimage] = DELETED_KEY_FLAG

            # Iterate over the segment backwards to find the last key entry.
            ids.last_key_entry_ptr = next(
                (key_ptr for i in range(1, segment_size)
                 if memory[key_ptr := ids.dict_ptr.address_ - ids.DictAccess.SIZE * i] == ids.felt_key),
                0
            )
        else:
            # Nothing to do.
            ids.dict_ptr.prev_value = 0
            ids.last_key_entry_ptr = 0
    %}
    dict_ptr.key = felt_key;

    if (last_key_entry_ptr != 0) {
        // The prover returns __a__ key: we can only verify that it matches the key we provided, but not that it is the last one.
        // See other assertions in `hashdict_delete` functions, on how to properly log that dict access.
        assert [last_key_entry_ptr].key = felt_key;
        return (felt_key=felt_key, last_key_entry_ptr=last_key_entry_ptr);
    }

    // The prover says that the key is not present: as such we must verify that the prev_value it returned is the default value `0`.
    // Note: this is because all hashdict values are pointers, `0` identifies a null pointer.
    assert dict_ptr.prev_value = 0;
    return (felt_key=felt_key, last_key_entry_ptr=last_key_entry_ptr);
}

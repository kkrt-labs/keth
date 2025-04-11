from starkware.cairo.common.builtin_poseidon.poseidon import poseidon_hash, poseidon_hash_many
from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.registers import get_label_location
from ethereum_types.numeric import U256, U256Struct
from ethereum.utils.numeric import U256__eq__
from ethereum.cancun.fork_types import (
    OptionalAccount,
    AddressAccountDictAccess,
    TupleAddressBytes32U256DictAccess,
    account_eq_without_storage_root,
)
from ethereum.cancun.state import State
from cairo_core.comparison import is_ptr_equal
from mpt.types import (
    AccountDiff,
    AccountDiffStruct,
    AddressAccountDiffEntry,
    StorageDiffEntry,
    StorageDiff,
    StorageDiffEntryStruct,
    AddressAccountDiffEntryStruct,
)

from ethereum.utils.numeric import divmod

// @notice Computes the Poseidon hash of an account diff entry
// @dev Hashes the address, previous account state (if exists), and new account state
// @param diff The account diff entry containing the address and account states
// @return The Poseidon hash of the account diff entry
func poseidon_account_diff{poseidon_ptr: PoseidonBuiltin*}(diff: AddressAccountDiffEntry) -> felt {
    alloc_locals;
    let (buffer) = alloc();

    assert buffer[0] = diff.value.key.value;

    local offset;

    // A prev_account can be null if the account did not exist in the pre-state.
    if (cast(diff.value.prev_value.value, felt) != 0) {
        // Inline the prev Account struct as we must hash values, not pointers to values
        assert buffer[1] = diff.value.prev_value.value.nonce.value;
        assert buffer[2] = diff.value.prev_value.value.balance.value.low;
        assert buffer[3] = diff.value.prev_value.value.balance.value.high;
        assert buffer[4] = diff.value.prev_value.value.code_hash.value.low;
        assert buffer[5] = diff.value.prev_value.value.code_hash.value.high;
        // We only hash the account's storage root at the start of the block, as
        // we can't compute the post storage root using only the partial state
        // changes. This is sufficient as we commit to all storage diffs.
        assert buffer[6] = diff.value.prev_value.value.storage_root.value.low;
        assert buffer[7] = diff.value.prev_value.value.storage_root.value.high;
        assert offset = 8;
    } else {
        assert offset = 1;
    }

    // TODO: This technically only happens in cases where the account was deleted,
    // which can only happen in case of a same-transaction selfdestruct, meaning the account was
    // originally Null. As such: once we skip computing hashes when there's no diff, this should be removed
    if (cast(diff.value.new_value.value, felt) != 0) {
        // Inline the new Account
        assert buffer[offset] = diff.value.new_value.value.nonce.value;
        assert buffer[offset + 1] = diff.value.new_value.value.balance.value.low;
        assert buffer[offset + 2] = diff.value.new_value.value.balance.value.high;
        assert buffer[offset + 3] = diff.value.new_value.value.code_hash.value.low;
        assert buffer[offset + 4] = diff.value.new_value.value.code_hash.value.high;
        let (account_diff_hash) = poseidon_hash_many(offset + 5, buffer);
        return account_diff_hash;
    }

    let (account_diff_hash) = poseidon_hash_many(offset, buffer);
    return account_diff_hash;
}

// @notice Computes the Poseidon hash of a storage diff entry
// @dev Hashes the storage key, previous value, and new value.
//      The prev and new value must not be set to null pointers.
// @param diff The storage diff entry containing the key and storage values
// @return The Poseidon hash of the storage diff entry
func poseidon_storage_diff{poseidon_ptr: PoseidonBuiltin*}(diff: StorageDiffEntry) -> felt {
    alloc_locals;
    let (buffer) = alloc();

    assert buffer[0] = diff.value.key.value;
    assert buffer[1] = diff.value.prev_value.value.low;
    assert buffer[2] = diff.value.prev_value.value.high;
    assert buffer[3] = diff.value.new_value.value.low;
    assert buffer[4] = diff.value.new_value.value.high;

    let (storage_diff_hash) = poseidon_hash_many(5, buffer);
    return storage_diff_hash;
}

// Trie diff segment hashing

// @notice Hashes a segment of account diffs into a single commitment
// @dev All entries are hashed in order and accumulated in a buffer
//      The buffer is then hashed to produce the final commitment
// @param account_diff The account diff struct containing all diff entries
// @return The hash commitment of all account diffs, or 0 if empty
func hash_account_diff_segment{poseidon_ptr: PoseidonBuiltin*}(account_diff: AccountDiff) -> felt {
    alloc_locals;
    let len = account_diff.value.len;
    if (len == 0) {
        return 0;
    }
    let (hashes_buffer) = alloc();
    let buffer_len = _accumulate_diff_hashes(hashes_buffer, account_diff, 0);
    let (final_hash) = poseidon_hash_many(buffer_len, hashes_buffer);
    return final_hash;
}

// @notice Helper function to accumulate account diff hashes into a buffer
// @dev Recursively processes each account diff entry and stores its hash
// @param buffer The buffer to store the accumulated hashes
// @param account_diff The account diff struct containing all entries
// @param i The current index being processed
// @return The number of hashes accumulated (buffer length)
func _accumulate_diff_hashes{poseidon_ptr: PoseidonBuiltin*}(
    buffer: felt*, account_diff: AccountDiff, i: felt
) -> felt {
    if (i == account_diff.value.len) {
        return i;
    }
    let current_diff = account_diff.value.data[i];
    let current_hash = poseidon_account_diff(current_diff);
    assert buffer[i] = current_hash;
    return _accumulate_diff_hashes(buffer, account_diff, i + 1);
}

// @notice Hashes a segment of storage diffs into a single commitment
// @dev All entries are hashed in order and accumulated in a buffer
//      The buffer is then hashed to produce the final commitment
// @param storage_diff The storage diff struct containing all diff entries
// @return The hash commitment of all storage diffs, or 0 if empty
func hash_storage_diff_segment{poseidon_ptr: PoseidonBuiltin*}(storage_diff: StorageDiff) -> felt {
    alloc_locals;
    let len = storage_diff.value.len;
    if (len == 0) {
        return 0;
    }
    let (hashes_buffer) = alloc();
    let buffer_len = _accumulate_storage_diff_hashes(hashes_buffer, storage_diff, 0);
    let (final_hash) = poseidon_hash_many(buffer_len, hashes_buffer);
    return final_hash;
}

// @notice Helper function to accumulate storage diff hashes into a buffer
// @dev Recursively processes each storage diff entry and stores its hash
// @param buffer The buffer to store the accumulated hashes
// @param storage_diff The storage diff struct containing all entries
// @param i The current index being processed
// @return The number of hashes accumulated (buffer length)
func _accumulate_storage_diff_hashes{poseidon_ptr: PoseidonBuiltin*}(
    buffer: felt*, storage_diff: StorageDiff, i: felt
) -> felt {
    if (i == storage_diff.value.len) {
        return i;
    }
    let current_diff = storage_diff.value.data[i];
    tempvar key = current_diff.value.key;

    let current_hash = poseidon_storage_diff(current_diff);
    assert buffer[i] = current_hash;
    return _accumulate_storage_diff_hashes(buffer, storage_diff, i + 1);
}

// State diff hashing

// @notice Computes a hash commitment for all account diffs in a state
// @dev Processes the account diffs stored in the main trie of the state
//      Any entry where prev_value == new_value is skipped in the computation of the hash.
// @param state The state containing account diffs in its main trie
// @return The hash commitment of all state account diffs, or 0 if empty
func hash_state_account_diff{range_check_ptr, poseidon_ptr: PoseidonBuiltin*}(
    state: State
) -> felt {
    alloc_locals;
    let dict_ptr_start = state.value._main_trie.value._data.value.dict_ptr_start;
    let dict_ptr_end = state.value._main_trie.value._data.value.dict_ptr;
    let (len, _) = divmod(dict_ptr_end - dict_ptr_start, AddressAccountDictAccess.SIZE);
    if (len == 0) {
        return 0;
    }

    let (hashes_buffer) = alloc();
    let buffer_end = _accumulate_state_diff_hashes(hashes_buffer, dict_ptr_start, 0, len);
    let buffer_len = buffer_end - hashes_buffer;
    let (final_hash) = poseidon_hash_many(buffer_len, hashes_buffer);
    return final_hash;
}

// @notice Helper function to accumulate state account diff hashes
// @dev Processes a segment of state account diffs and accumulates their hashes
//      If both accounts have are the same (not taking into account the storage root which is not updated),
//      we skip the hash computation.
// @param buffer The buffer to store the accumulated hashes
// @param state_account_diff Pointer to the first state account diff
// @param i The current index being processed
// @param len Total number of entries to process
// @return The number of hashes accumulated (buffer length)
func _accumulate_state_diff_hashes{poseidon_ptr: PoseidonBuiltin*}(
    buffer: felt*, state_account_diff: AddressAccountDictAccess*, i: felt, len: felt
) -> felt* {
    alloc_locals;
    if (i == len) {
        return buffer;
    }
    let current_diff_ptr = state_account_diff + i * AddressAccountDictAccess.SIZE;

    let (ptr_eq, comparison_ok) = is_ptr_equal(
        cast(current_diff_ptr.prev_value.value, felt*),
        cast(current_diff_ptr.new_value.value, felt*),
    );
    if (ptr_eq.value != 0 and comparison_ok.value != 0) {
        return _accumulate_state_diff_hashes(buffer, state_account_diff, i + 1, len);
    }

    // If the pointers are not equal, or we cannot compare them, we still need to do value comparison.

    // Storage diffs are handled separately, so we can compare the account diffs without the storage root.
    let prev_eq_new = account_eq_without_storage_root(
        OptionalAccount(current_diff_ptr.prev_value.value),
        OptionalAccount(current_diff_ptr.new_value.value),
    );
    if (prev_eq_new.value != 0) {
        return _accumulate_state_diff_hashes(buffer, state_account_diff, i + 1, len);
    }

    // We can cast the AddressAccountDictAccess to an AddressAccountDiffEntryStruct as the two underlying types are identical.
    // TODO: maybe delete AddressAccountDiffEntryStruct altogether ?
    let current_hash = poseidon_account_diff(
        AddressAccountDiffEntry(cast(current_diff_ptr, AddressAccountDiffEntryStruct*))
    );
    assert [buffer] = current_hash;
    return _accumulate_state_diff_hashes(buffer + 1, state_account_diff, i + 1, len);
}

// @notice Computes a hash commitment for all storage diffs in a state
// @dev Processes the storage diffs stored in the storage tries of the state
//      Any entry where prev_value == new_value is skipped in the computation of the hash.
// @param state The state containing storage diffs in its storage tries
// @return The hash commitment of all state storage diffs, or 0 if empty
func hash_state_storage_diff{range_check_ptr, poseidon_ptr: PoseidonBuiltin*}(
    state: State
) -> felt {
    alloc_locals;

    let dict_ptr_start = state.value._storage_tries.value._data.value.dict_ptr_start;
    let dict_ptr_end = state.value._storage_tries.value._data.value.dict_ptr;

    let (len, _) = divmod(dict_ptr_end - dict_ptr_start, TupleAddressBytes32U256DictAccess.SIZE);
    if (len == 0) {
        return 0;
    }

    // We cast the state dict pointer to a StorageDiffEntry pointer as the two underlying types are identical.
    let casted_dict_ptr_start = cast(dict_ptr_start, TupleAddressBytes32U256DictAccess*);
    let (hashes_buffer) = alloc();
    let buffer_end = _accumulate_state_storage_diff_hashes(
        hashes_buffer, casted_dict_ptr_start, 0, len
    );
    let buffer_len = buffer_end - hashes_buffer;
    let (final_hash) = poseidon_hash_many(buffer_len, hashes_buffer);

    return final_hash;
}

// @notice Helper function to accumulate state storage diff hashes
// @dev Processes a segment of state storage diffs and accumulates their hashes
// @param buffer The buffer to store the accumulated hashes
// @param state_storage_diff Pointer to the first state storage diff
// @param i The current index being processed
// @param len Total number of entries to process
// @return The number of hashes accumulated (buffer length)
func _accumulate_state_storage_diff_hashes{poseidon_ptr: PoseidonBuiltin*}(
    buffer: felt*, state_storage_diff: TupleAddressBytes32U256DictAccess*, i: felt, len: felt
) -> felt* {
    alloc_locals;
    if (i == len) {
        return buffer;
    }
    let current_diff_ptr = state_storage_diff + i * TupleAddressBytes32U256DictAccess.SIZE;

    // Check if pointers are equal, meaning that there is no storage diff.
    let (ptr_eq, comparison_ok) = is_ptr_equal(
        cast(current_diff_ptr.new_value.value, felt*),
        cast(current_diff_ptr.prev_value.value, felt*),
    );
    if (ptr_eq.value != 0 and comparison_ok.value != 0) {
        return _accumulate_state_storage_diff_hashes(buffer, state_storage_diff, i + 1, len);
    }

    // If the pointers are not equal, or we cannot compare them, we still need to do value comparison.

    // Due to the behavior of storage_tries, a value set to U256(0) will be "deleted" by writing a null pointer instead.
    // If that's the case, we set the value to an explicit U256(0) to be able to hash the entry.
    local new_value: U256;
    if (current_diff_ptr.new_value.value == 0) {
        assert new_value = U256(new U256Struct(0, 0));
    } else {
        assert new_value = current_diff_ptr.new_value;
    }

    // Check whether the pre and post storage values are the same, creating no diff.
    let prev_value = current_diff_ptr.prev_value;
    let prev_eq_new = U256__eq__(prev_value, new_value);
    if (prev_eq_new.value != 0) {
        return _accumulate_state_storage_diff_hashes(buffer, state_storage_diff, i + 1, len);
    }

    tempvar storage_diff_entry = StorageDiffEntry(
        new StorageDiffEntryStruct(
            key=current_diff_ptr.key, prev_value=prev_value, new_value=new_value
        ),
    );
    let current_hash = poseidon_storage_diff(storage_diff_entry);
    assert [buffer] = current_hash;
    return _accumulate_state_storage_diff_hashes(buffer + 1, state_storage_diff, i + 1, len);
}

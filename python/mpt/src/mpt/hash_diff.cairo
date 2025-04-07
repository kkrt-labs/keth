from starkware.cairo.common.builtin_poseidon.poseidon import poseidon_hash, poseidon_hash_many
from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.alloc import alloc
from ethereum_types.numeric import U256, U256Struct
from ethereum.cancun.fork_types import AddressAccountDictAccess, TupleAddressBytes32U256DictAccess
from ethereum.cancun.state import State
from mpt.types import (
    AccountDiff,
    AddressAccountDiffEntry,
    StorageDiffEntry,
    StorageDiff,
    StorageDiffEntryStruct,
    AddressAccountDiffEntryStruct,
)

from cairo_core.control_flow import raise

func poseidon_account_diff{poseidon_ptr: PoseidonBuiltin*}(diff: AddressAccountDiffEntry) -> felt {
    alloc_locals;
    let (buffer) = alloc();

    assert buffer[0] = diff.value.key.value;

    local offset;
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

    // Inline the new Account
    assert buffer[offset] = diff.value.new_value.value.nonce.value;
    assert buffer[offset + 1] = diff.value.new_value.value.balance.value.low;
    assert buffer[offset + 2] = diff.value.new_value.value.balance.value.high;
    assert buffer[offset + 3] = diff.value.new_value.value.code_hash.value.low;
    assert buffer[offset + 4] = diff.value.new_value.value.code_hash.value.high;

    let (account_diff_hash) = poseidon_hash_many(offset + 5, buffer);
    return account_diff_hash;
}

func poseidon_storage_diff{poseidon_ptr: PoseidonBuiltin*}(diff: StorageDiffEntry) -> felt {
    alloc_locals;
    let (buffer) = alloc();

    assert buffer[0] = diff.value.key.value;
    // Inline the prev storage value (U256)
    assert buffer[1] = diff.value.prev_value.value.low;
    assert buffer[2] = diff.value.prev_value.value.high;
    // Inline the new storage value (U256)
    assert buffer[3] = diff.value.new_value.value.low;
    assert buffer[4] = diff.value.new_value.value.high;

    let (storage_diff_hash) = poseidon_hash_many(5, buffer);
    return storage_diff_hash;
}

func hash_account_diff_segment{poseidon_ptr: PoseidonBuiltin*}(account_diff: AccountDiff) -> felt {
    alloc_locals;
    let len = account_diff.value.len;
    if (len == 0) {
        // TODO: Do we return 0 as the hash of an empty segment?
        // We don't want to raise here as a block could have 0 account diffs.
        return 0;
    }
    let accumulator = poseidon_account_diff(account_diff.value.data[0]);
    let final_hash = _hash_account_diff_inner(accumulator, account_diff.value.data, 1, len);
    return final_hash;
}

func _hash_account_diff_inner{poseidon_ptr: PoseidonBuiltin*}(
    accumulator: felt, start_ptr: AddressAccountDiffEntry*, i: felt, len: felt
) -> felt {
    if (i == len) {
        return accumulator;
    }
    let next_hash = poseidon_account_diff(start_ptr[i]);

    let (buffer) = alloc();
    assert buffer[0] = accumulator;
    assert buffer[1] = next_hash;
    let (accumulator) = poseidon_hash_many(2, buffer);

    return _hash_account_diff_inner(accumulator, start_ptr, i + 1, len);
}

func hash_state_account_diff{poseidon_ptr: PoseidonBuiltin*}(state: State) -> felt {
    alloc_locals;
    let dict_ptr_start = state.value._main_trie.value._data.value.dict_ptr_start;
    let dict_ptr_end = state.value._main_trie.value._data.value.dict_ptr;
    let len = dict_ptr_end - dict_ptr_start;
    if (len == 0) {
        return 0;
    }

    // We cast the state dict pointer to an AddressAccountDiffEntry pointer as the two underlying types are identical.
    let casted_dict_ptr_start = cast(dict_ptr_start, AddressAccountDiffEntryStruct*);
    let accumulator = poseidon_account_diff(AddressAccountDiffEntry(casted_dict_ptr_start));
    tempvar start_ptr = new AddressAccountDiffEntry(casted_dict_ptr_start);
    let final_hash = _hash_account_diff_inner(accumulator, start_ptr, 1, len);
    return final_hash;
}

func hash_storage_diff_segment{poseidon_ptr: PoseidonBuiltin*}(storage_diff: StorageDiff) -> felt {
    alloc_locals;
    let len = storage_diff.value.len;
    if (len == 0) {
        return 0;
    }
    let accumulator = poseidon_storage_diff(storage_diff.value.data[0]);
    let final_hash = _hash_storage_diff_inner(accumulator, storage_diff.value.data, 1, len);
    return final_hash;
}

func _hash_storage_diff_inner{poseidon_ptr: PoseidonBuiltin*}(
    accumulator: felt, start_ptr: StorageDiffEntry*, i: felt, len: felt
) -> felt {
    if (i == len) {
        return accumulator;
    }
    let next_hash = poseidon_storage_diff(start_ptr[i]);

    let (buffer) = alloc();
    assert buffer[0] = accumulator;
    assert buffer[1] = next_hash;
    let (accumulator) = poseidon_hash_many(2, buffer);

    return _hash_storage_diff_inner(accumulator, start_ptr, i + 1, len);
}

func hash_state_storage_diff{poseidon_ptr: PoseidonBuiltin*}(state: State) -> felt {
    alloc_locals;

    let dict_ptr_start = state.value._storage_tries.value._data.value.dict_ptr_start;
    let dict_ptr_end = state.value._storage_tries.value._data.value.dict_ptr;

    let len = dict_ptr_end - dict_ptr_start;
    if (len == 0) {
        return 0;
    }

    // We cast the state dict pointer to a StorageDiffEntry pointer as the two underlying types are identical.
    let casted_dict_ptr_start = cast(dict_ptr_start, StorageDiffEntryStruct*);

    let accumulator = poseidon_storage_diff(StorageDiffEntry(casted_dict_ptr_start));
    tempvar start_ptr = new StorageDiffEntry(casted_dict_ptr_start);
    let final_hash = _hash_storage_diff_inner(accumulator, start_ptr, 1, len);

    return final_hash;
}

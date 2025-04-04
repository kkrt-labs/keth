from starkware.cairo.common.builtin_poseidon.poseidon import poseidon_hash, poseidon_hash_many
from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.alloc import alloc
from ethereum_types.numeric import U256, U256Struct
from mpt.trie_diff import AddressAccountDiffEntry, Account, StorageDiffEntryStruct, StorageDiffEntry

func poseidon_account_diff{poseidon_ptr: PoseidonBuiltin*}(diff: AddressAccountDiffEntry) -> felt {
    alloc_locals;
    let (buffer) = alloc();

    assert buffer[0] = diff.value.key.value;

    // Inline the prev Account struct as we must hash values, not pointers to values
    assert buffer[1] = diff.value.prev_value.value.nonce.value;
    assert buffer[2] = diff.value.prev_value.value.balance.value.low;
    assert buffer[3] = diff.value.prev_value.value.balance.value.high;
    assert buffer[4] = diff.value.prev_value.value.code_hash.value.low;
    assert buffer[5] = diff.value.prev_value.value.code_hash.value.high;
    assert buffer[6] = diff.value.prev_value.value.storage_root.value.low;
    assert buffer[7] = diff.value.prev_value.value.storage_root.value.high;

    // Inline the new Account
    assert buffer[8] = diff.value.new_value.value.nonce.value;
    assert buffer[9] = diff.value.new_value.value.balance.value.low;
    assert buffer[10] = diff.value.new_value.value.balance.value.high;
    assert buffer[11] = diff.value.new_value.value.code_hash.value.low;
    assert buffer[12] = diff.value.new_value.value.code_hash.value.high;
    assert buffer[13] = diff.value.new_value.value.storage_root.value.low;
    assert buffer[14] = diff.value.new_value.value.storage_root.value.high;

    let (account_diff_hash) = poseidon_hash_many(15, buffer);
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

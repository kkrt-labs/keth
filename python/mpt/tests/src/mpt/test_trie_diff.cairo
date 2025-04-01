from starkware.cairo.common.cairo_builtins import PoseidonBuiltin, BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.alloc import alloc
from mpt.trie_diff import (
    _process_account_diff,
    _process_storage_diff,
    MappingBytes32Address,
    AddressAccountNodeDiffEntry,
    AddressAccountNodeDiffEntryStruct,
    AccountDiff,
    AccountDiffStruct,
    StorageDiff,
    StorageDiffStruct,
    StorageDiffEntry,
    StorageDiffEntryStruct,
    MappingBytes32Bytes32,
    NodeStore,
)
from ethereum_types.bytes import Bytes32
from ethereum.cancun.trie import OptionalLeafNode
from ethereum.cancun.fork_types import Address, TupleAddressBytes32U256DictAccess
from ethereum.cancun.trie import Bytes32U256DictAccess

func test__process_account_diff{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}(
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    path: Bytes32,
    left: OptionalLeafNode,
    right: OptionalLeafNode,
) -> AccountDiff {
    alloc_locals;

    let (main_trie_start: AddressAccountNodeDiffEntry*) = alloc();
    let main_trie_end = main_trie_start;

    let (storage_trie_start: StorageDiffEntry*) = alloc();
    let storage_trie_end = storage_trie_start;

    _process_account_diff{
        node_store=node_store,
        address_preimages=address_preimages,
        storage_key_preimages=storage_key_preimages,
        main_trie_end=main_trie_end,
        storage_tries_end=storage_trie_end,
    }(path=path, left=left, right=right);

    tempvar account_diff = AccountDiff(
        new AccountDiffStruct(data=main_trie_start, len=main_trie_end - main_trie_start)
    );

    return account_diff;
}

func test__process_storage_diff{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}(
    storage_key_preimages: MappingBytes32Bytes32,
    path: Bytes32,
    address: Address,
    left: OptionalLeafNode,
    right: OptionalLeafNode,
) -> StorageDiff {
    alloc_locals;

    let (storage_tries_start: StorageDiffEntry*) = alloc();
    let storage_tries_end = storage_tries_start;
    _process_storage_diff{
        storage_key_preimages=storage_key_preimages, storage_tries_end=storage_tries_end
    }(address=address, path=path, left=left, right=right);

    tempvar storage_diff = StorageDiff(
        new StorageDiffStruct(data=storage_tries_start, len=storage_tries_end - storage_tries_start)
    );

    return storage_diff;
}

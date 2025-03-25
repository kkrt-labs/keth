from starkware.cairo.common.cairo_builtins import PoseidonBuiltin, BitwiseBuiltin
from starkware.cairo.common.alloc import alloc
from mpt.trie_diff import (
    _process_account_diff,
    _process_storage_diff,
    MappingBytes32Address,
    AddressAccountNodeDictAccess,
    MappingBytes32Bytes32,
)
from ethereum_types.bytes import Bytes32
from ethereum.cancun.trie import OptionalLeafNode
from ethereum.cancun.fork_types import Address
from ethereum.cancun.trie import Bytes32U256DictAccess

func test__process_account_diff{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, poseidon_ptr: PoseidonBuiltin*
}(
    address_preimages: MappingBytes32Address,
    path: Bytes32,
    left: OptionalLeafNode,
    right: OptionalLeafNode,
) -> AddressAccountNodeDictAccess* {
    alloc_locals;

    let (main_trie_start: AddressAccountNodeDictAccess*) = alloc();
    let main_trie_end = main_trie_start;
    _process_account_diff{address_preimages=address_preimages, main_trie_end=main_trie_end}(
        path=path, left=left, right=right
    );

    return main_trie_start;
}

func test__process_storage_diff{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, poseidon_ptr: PoseidonBuiltin*
}(
    storage_key_preimages: MappingBytes32Bytes32,
    path: Bytes32,
    address: Address,
    left: OptionalLeafNode,
    right: OptionalLeafNode,
) -> Bytes32U256DictAccess* {
    alloc_locals;

    let (storage_trie_start: Bytes32U256DictAccess*) = alloc();
    let storage_trie_end = storage_trie_start;
    _process_storage_diff{
        storage_key_preimages=storage_key_preimages, storage_trie_end=storage_trie_end
    }(address=address, path=path, left=left, right=right);

    return storage_trie_start;
}

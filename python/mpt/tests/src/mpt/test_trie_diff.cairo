from starkware.cairo.common.cairo_builtins import PoseidonBuiltin, BitwiseBuiltin
from starkware.cairo.common.alloc import alloc
from mpt.trie_diff import _process_account_diff, MappingBytes32Address, AddressAccountNodeDictAccess
from ethereum_types.bytes import Bytes32
from ethereum.cancun.trie import OptionalLeafNode

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

from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.dict import DictAccess

from ethereum.crypto.hash import Hash32
from ethereum.cancun.fork_types import Address, TupleAddressBytes32U256DictAccess
from ethereum_types.bytes import Bytes, OptionalBytes, Bytes32, OptionalBytes32, HashedBytes32
from ethereum_types.numeric import U256, Uint
from ethereum.cancun.trie import LeafNode, OptionalInternalNode, InternalNodeEnum
from ethereum_rlp.rlp import Extended
from ethereum.utils.bytes import Bytes_to_Bytes32
from legacy.utils.dict import hashdict_read
from starkware.cairo.common.alloc import alloc

// NodeStore is a mapping of node hashes to their corresponding InternalNode
// In the world state DB given as input to the program
// This is used to store state and storage MPT nodes
// used to prove the state transition function
struct NodeStore {
    value: NodeStoreStruct*,
}
struct NodeStoreStruct {
    dict_ptr_start: NodeStoreDictAccess*,
    dict_ptr: NodeStoreDictAccess*,
}

struct NodeStoreDictAccess {
    key: HashedBytes32,
    prev_value: OptionalInternalNode,
    new_value: OptionalInternalNode,
}
// AddressPreimages is a mapping of keccak(address) to their corresponding preimages
// As per the specification, MPT state nodes paths are keccak(address)
// This mapping is used to retrieve the address given a full state path
struct MappingBytes32Address {
    value: MappingBytes32AddressStruct*,
}
struct MappingBytes32AddressStruct {
    dict_ptr_start: Bytes32OptionalAddressDictAccess*,
    dict_ptr: Bytes32OptionalAddressDictAccess*,
}
struct Bytes32OptionalAddressDictAccess {
    key: HashedBytes32,
    prev_value: Address,
    new_value: Address,
}

// StorageKeyPreimages is a mapping of keccak(storage_key) to their corresponding preimages
// As per the specification, MPT storage nodes paths are keccak(storage_key)
// This mapping is used to retrieve the storage key given a full storage path for a given address
struct MappingBytes32Bytes32 {
    value: MappingBytes32Bytes32Struct*,
}
struct MappingBytes32Bytes32Struct {
    dict_ptr_start: Bytes32OptionalBytes32DictAccess*,
    dict_ptr: Bytes32OptionalBytes32DictAccess*,
}
struct Bytes32OptionalBytes32DictAccess {
    key: HashedBytes32,
    prev_value: OptionalBytes32,
    new_value: OptionalBytes32,
}

// TrieDiff records the difference between a "pre" world state and a "post" world state
// It contains the differences in the state and storage trie nodes
// It is used to prove the state transition function of the Ethereum Execution Layer
struct TrieDiff {
    value: TrieDiffStruct*,
}
struct TrieDiffStruct {
    _main_trie_start: AddressAccountNodeDictAccess*,
    _main_trie_end: AddressAccountNodeDictAccess*,
    _storage_tries_start: TupleAddressBytes32U256DictAccess*,
    _storage_tries_end: TupleAddressBytes32U256DictAccess*,
}
// AccountNode is the format of
// the account inside the Ethereum state MPT
struct AccountNode {
    value: AccountNodeStruct*,
}
struct AccountNodeStruct {
    balance: U256,
    code_hash: Hash32,
    nonce: Uint,
    storage_root: Hash32,
}
struct AddressAccountNodeDictAccess {
    key: Address,
    prev_value: AccountNode,
    new_value: AccountNode,
}

// Process the difference between two account leaf nodes
func _process_account_diff{}(path: Bytes32, left: LeafNode, right: LeafNode) -> () {
    return ();
}

// Process the difference between two storage leaf nodes
func _process_storage_diff{}(address: Address, path: Bytes32, left: LeafNode, right: LeafNode) -> (
    ) {
    return ();
}

// Classify Extended that can be found in a BranchNode subnodes or ExtensionNode subnode
// Into either a Node hash, or an embedded node
// If node hash, then resolve the node hash into an InternalNode using the node store
// If embedded node, then return RLP.decode the embedded node
func _resolve{range_check_ptr, poseidon_ptr: PoseidonBuiltin*}(
    node: Extended, node_store: NodeStore
) -> OptionalInternalNode {
    alloc_locals;

    let enum = node.value;
    if (cast(enum.bytes.value, felt) != 0) {
        // Case 1: it is a node hash
        if (enum.bytes.value.len == 32) {
            let node_hash = Bytes_to_Bytes32(enum.bytes);
            let result = node_store_get{poseidon_ptr=poseidon_ptr, node_store=node_store}(
                node_hash
            );
            return result;
        }
        // Case 2: it is an embedded node, we have to RLP decode it
        // TODO: handle embedded case
    }

    // We're not supposed to get anything but bytes in the enum
    // TODO: raise error in any other case: bytearray, sequence, bool, uint etc.

    let result = OptionalInternalNode(cast(0, InternalNodeEnum*));
    return result;
}

// Recursively compute the difference between two Ethereum tries starting from left and right
func _compute_diff{}(
    left: Extended,
    right: Extended,
    path: Bytes,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    process_leaf: felt*,
) -> () {
    return ();
}

func node_store_get{poseidon_ptr: PoseidonBuiltin*, node_store: NodeStore}(
    node_hash: Hash32
) -> OptionalInternalNode {
    alloc_locals;
    let dict_ptr = cast(node_store.value.dict_ptr, DictAccess*);

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let (keys) = alloc();
    assert keys[0] = node_hash.value.low;
    assert keys[1] = node_hash.value.high;

    // Read from the dictionary using the hash as key
    let (pointer) = hashdict_read{dict_ptr=dict_ptr}(2, keys);

    let new_dict_ptr = cast(dict_ptr, NodeStoreDictAccess*);
    tempvar node_store = NodeStore(
        new NodeStoreStruct(node_store.value.dict_ptr_start, new_dict_ptr)
    );
    // Cast the result to an OptionalInternalNode and return
    tempvar res = OptionalInternalNode(cast(pointer, InternalNodeEnum*));
    return res;
}

from ethereum.crypto.hash import Hash32
from ethereum.cancun.fork_types import Address, TupleAddressBytes32U256DictAccess
from ethereum_types.bytes import Bytes, OptionalBytes, Bytes32
from ethereum_types.numeric import U256, Uint
from ethereum.cancun.trie import LeafNode, OptionalInternalNode, InternalNodeEnum
from ethereum_rlp.rlp import Extended

// NodeStore is a mapping of node hashes to their corresponding InternalNode
// In the world state DB given as input to the program
// This is used to store state and storage MPT nodes
// used to prove the state transition function
struct NodeStore {
    value: NodeStoreStruct*,
}
struct NodeStoreStruct {
    key: Hash32,
    prev_value: OptionalInternalNode,
    new_value: OptionalInternalNode,
}

// AddressPreimages is a mapping of keccak(address) to their corresponding preimages
// As per the specification, MPT state nodes paths are keccak(address)
// This mapping is used to retrieve the address given a full state path
struct AddressPreimages {
    value: AddressPreimagesStruct*,
}
struct AddressPreimagesStruct {
    dict_ptr_start: Hash32OptionalAddressDictAccess*,
    dict_ptr: Hash32OptionalAddressDictAccess*,
}
struct Hash32OptionalAddressDictAccess {
    key: Hash32,
    prev_value: Address,
    new_value: Address,
}

// StorageKeyPreimages is a mapping of keccak(storage_key) to their corresponding preimages
// As per the specification, MPT storage nodes paths are keccak(storage_key)
// This mapping is used to retrieve the storage key given a full storage path for a given address
struct StorageKeyPreimages {
    value: StorageKeyPreimagesStruct*,
}
struct StorageKeyPreimagesStruct {
    dict_ptr_start: Hash32OptionalBytes32DictAccess*,
    dict_ptr: Hash32OptionalBytes32DictAccess*,
}
struct Hash32OptionalBytes32DictAccess {
    key: Hash32,
    prev_value: Bytes32,
    new_value: Bytes32,
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
func _process_storage_diff{}(path: Bytes32, left: LeafNode, right: LeafNode, address: Address) -> (
    ) {
    return ();
}

func _resolve{}(node: Extended) -> OptionalInternalNode {
    // Classify Extended that can be found in a BranchNode subnodes or ExtensionNode subnode
    // Into either a Node hash, or an embedded node
    // If node hash, then resolve the node hash into an InternalNode using the node store
    // If embedded node, then return RLP.decode the embedded node
    let result = OptionalInternalNode(cast(0, InternalNodeEnum*));
    return result;
}

// Recursively compute the difference between two Ethereum tries starting from left and right
func _compute_diff{}(
    left: Extended,
    right: Extended,
    path: Bytes,
    node_store: NodeStore,
    address_preimages: AddressPreimages,
    storage_key_preimages: StorageKeyPreimages,
    process_leaf: felt*,
) -> () {
    return ();
}

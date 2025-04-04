from ethereum_types.bytes import HashedBytes32, Bytes32, Bytes, String
from ethereum.cancun.trie import (
    LeafNode,
    OptionalInternalNode,
    ExtensionNode,
    BranchNode,
    SequenceExtended,
)
from ethereum.cancun.fork_types import Address, HashedTupleAddressBytes32
from ethereum_types.numeric import U256, Uint, Bool
from ethereum.crypto.hash import Hash32

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
    dict_ptr_start: Bytes32Bytes32DictAccess*,
    dict_ptr: Bytes32Bytes32DictAccess*,
}
struct Bytes32Bytes32DictAccess {
    key: HashedBytes32,
    prev_value: Bytes32,
    new_value: Bytes32,
}

struct AccountDiff {
    value: AccountDiffStruct*,
}
struct AccountDiffStruct {
    data: AddressAccountNodeDiffEntry*,
    len: felt,
}

struct StorageDiff {
    value: StorageDiffStruct*,
}
struct StorageDiffStruct {
    data: StorageDiffEntry*,
    len: felt,
}

struct StorageDiffEntry {
    value: StorageDiffEntryStruct*,
}

struct StorageDiffEntryStruct {
    key: HashedTupleAddressBytes32,
    prev_value: U256,
    new_value: U256,
}

// AccountNode is the format of
// the account inside the Ethereum state MPT
struct AccountNode {
    value: AccountNodeStruct*,
}
struct AccountNodeStruct {
    nonce: Uint,
    balance: U256,
    code_hash: Hash32,
    storage_root: Hash32,
}

struct AddressAccountNodeDiffEntryStruct {
    key: Address,
    prev_value: AccountNode,
    new_value: AccountNode,
}

struct AddressAccountNodeDiffEntry {
    value: AddressAccountNodeDiffEntryStruct*,
}

// Union of InternalNode (union type) and Extended (union type)
// Both sub unions must be inlined because in Python a Union[A, Union[B,C]] is just Union[A,B,C]
struct OptionalUnionInternalNodeExtended {
    value: OptionalUnionInternalNodeExtendedEnum*,
}
struct OptionalUnionInternalNodeExtendedEnum {
    leaf: LeafNode,
    extension: ExtensionNode,
    branch: BranchNode,
    sequence: SequenceExtended,
    bytearray: Bytes,
    bytes: Bytes,
    uint: Uint*,
    fixed_uint: Uint*,
    str: String,
    bool: Bool*,
}

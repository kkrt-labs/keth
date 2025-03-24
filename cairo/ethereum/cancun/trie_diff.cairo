from starkware.cairo.common.cairo_builtins import PoseidonBuiltin, BitwiseBuiltin
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.dict import DictAccess
from starkware.cairo.common.math_cmp import is_le

from ethereum.crypto.hash import Hash32
from ethereum.cancun.fork_types import Address, TupleAddressBytes32U256DictAccess
from ethereum_types.bytes import (
    Bytes,
    OptionalBytes,
    Bytes32,
    OptionalBytes32,
    HashedBytes32,
    BytesStruct,
)
from ethereum_types.numeric import U256, Uint
from ethereum.cancun.trie import (
    LeafNode,
    LeafNodeStruct,
    OptionalInternalNode,
    ExtensionNode,
    ExtensionNodeStruct,
    InternalNodeEnum,
    InternalNode,
    BranchNode,
    BranchNodeStruct,
    Subnodes,
    SubnodesStruct,
    bytes_to_nibble_list,
)
from ethereum_rlp.rlp import Extended, ExtendedImpl
from ethereum.utils.bytes import Bytes_to_Bytes32
from legacy.utils.dict import hashdict_read
from starkware.cairo.common.alloc import alloc
from cairo_core.control_flow import raise
from cairo_core.comparison import is_zero

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
func _resolve{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    node_store: NodeStore,
}(node: Extended) -> OptionalInternalNode {
    alloc_locals;

    let enum = node.value;

    if (cast(enum.bytes.value, felt) == 0 and cast(enum.sequence.value, felt) == 0) {
        raise('ValueError');
    }

    if (cast(enum.bytes.value, felt) != 0) {
        let bytes = enum.bytes;
        if (bytes.value.len != 32) {
            raise('ValueError');
        }
        // Case 1: it is a node hash
        // Get the node hash from the node store
        let node_hash = Bytes_to_Bytes32(bytes);
        let result = node_store_get{poseidon_ptr=poseidon_ptr, node_store=node_store}(node_hash);
        return result;
    }

    if (cast(enum.sequence.value, felt) != 0) {
        // Case 2: it is an embedded node, we deserialize it into an InternalNode
        let items_len = enum.sequence.value.len;
        let items = enum.sequence.value.data;

        // A node must have either 2 items (leaf/extension) or 17 items (branch)
        with_attr error_message("DecodingError") {
            assert (items_len - 2) * (items_len - 17) = 0;
        }

        // Case 1: Branch node (17 items)
        if (items_len == 17) {
            let branch_1 = ExtendedImpl.bytes(items[0].value.bytes);
            let branch_2 = ExtendedImpl.bytes(items[1].value.bytes);
            let branch_3 = ExtendedImpl.bytes(items[2].value.bytes);
            let branch_4 = ExtendedImpl.bytes(items[3].value.bytes);
            let branch_5 = ExtendedImpl.bytes(items[4].value.bytes);
            let branch_6 = ExtendedImpl.bytes(items[5].value.bytes);
            let branch_7 = ExtendedImpl.bytes(items[6].value.bytes);
            let branch_8 = ExtendedImpl.bytes(items[7].value.bytes);
            let branch_9 = ExtendedImpl.bytes(items[8].value.bytes);
            let branch_10 = ExtendedImpl.bytes(items[9].value.bytes);
            let branch_11 = ExtendedImpl.bytes(items[10].value.bytes);
            let branch_12 = ExtendedImpl.bytes(items[11].value.bytes);
            let branch_13 = ExtendedImpl.bytes(items[12].value.bytes);
            let branch_14 = ExtendedImpl.bytes(items[13].value.bytes);
            let branch_15 = ExtendedImpl.bytes(items[14].value.bytes);
            let branch_16 = ExtendedImpl.bytes(items[15].value.bytes);
            tempvar subnodes = Subnodes(
                new SubnodesStruct(
                    branch_1,
                    branch_2,
                    branch_3,
                    branch_4,
                    branch_5,
                    branch_6,
                    branch_7,
                    branch_8,
                    branch_9,
                    branch_10,
                    branch_11,
                    branch_12,
                    branch_13,
                    branch_14,
                    branch_15,
                    branch_16,
                ),
            );
            let value_item = ExtendedImpl.bytes(items[16].value.bytes);

            tempvar branch_node = BranchNode(
                new BranchNodeStruct(subnodes=subnodes, value=value_item)
            );

            // Return internal node with branch node variant
            tempvar result = OptionalInternalNode(
                new InternalNodeEnum(
                    leaf_node=LeafNode(cast(0, LeafNodeStruct*)),
                    extension_node=ExtensionNode(cast(0, ExtensionNodeStruct*)),
                    branch_node=branch_node,
                ),
            );

            return result;
        }

        // Case 2: Extension node (2 items)
        if (items_len == 2) {
            let prefix = items[0].value.bytes;
            let value = ExtendedImpl.bytes(items[1].value.bytes);

            let nibbles = bytes_to_nibble_list(prefix);
            let first_nibble = nibbles.value.data[0];
            // If the first nibble is 1 or 3, this means the real key is odd length and we need to remove the first nibble
            if ((first_nibble - 1) * (first_nibble - 3) == 0) {
                tempvar nibbles = Bytes(
                    new BytesStruct(prefix.value.data + 1, prefix.value.len - 1)
                );
            } else {
                // Else this means the real key is even length and we need to remove the first two nibbles (the flag itself and a padded zero)
                tempvar nibbles = Bytes(
                    new BytesStruct(prefix.value.data + 2, prefix.value.len - 2)
                );
            }
            let is_leaf = is_zero((first_nibble - 2) * (first_nibble - 3));

            if (is_leaf != 0) {
                tempvar leaf_node = LeafNode(new LeafNodeStruct(rest_of_key=nibbles, value=value));
                let extension_node = ExtensionNode(cast(0, ExtensionNodeStruct*));

                // Without this step, leaf_node reference will be revoked.
                tempvar leaf_node = leaf_node;
                tempvar extension_node = extension_node;
            } else {
                let leaf_node = LeafNode(cast(0, LeafNodeStruct*));
                tempvar extension_node = ExtensionNode(
                    new ExtensionNodeStruct(key_segment=nibbles, subnode=value)
                );

                // Without this step, leaf_node reference will be revoked.
                tempvar leaf_node = leaf_node;
                tempvar extension_node = extension_node;
            }

            tempvar result = OptionalInternalNode(
                new InternalNodeEnum(
                    leaf_node=leaf_node,
                    extension_node=extension_node,
                    branch_node=BranchNode(cast(0, BranchNodeStruct*)),
                ),
            );
            return result;
        }
    }

    with_attr error_message("Invalid node: expected embedded node") {
        jmp raise.raise_label;
    }
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

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import PoseidonBuiltin, BitwiseBuiltin
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.dict import DictAccess

from ethereum.crypto.hash import Hash32
from ethereum.cancun.fork_types import Address, TupleAddressBytes32U256DictAccess
from ethereum_types.bytes import (
    Bytes,
    OptionalBytes,
    Bytes32,
    Bytes32Struct,
    OptionalBytes32,
    BytesStruct,
    HashedBytes32,
    String,
)
from ethereum_types.numeric import U256, Uint, U256Struct
from ethereum.cancun.trie import (
    LeafNode,
    OptionalLeafNode,
    OptionalInternalNode,
    InternalNodeEnum,
    Bytes32U256DictAccess,
)
from ethereum_rlp.rlp import Extended, decode, U256_from_rlp
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import PoseidonBuiltin, BitwiseBuiltin
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.builtin_poseidon.poseidon import poseidon_hash, poseidon_hash_many
from legacy.utils.dict import hashdict_read, hashdict_write, dict_new_empty, dict_read
from cairo_core.control_flow import raise
from starkware.cairo.common.dict import DictAccess
from ethereum.utils.numeric import ceil32, divmod, U256_from_be_bytes, U256_le, Uint_from_be_bytes
from ethereum.utils.bytes import Bytes_to_Bytes32

from legacy.utils.dict import hashdict_read, hashdict_write, dict_new_empty, dict_read
from cairo_core.control_flow import raise
from mpt.utils import deserialize_to_internal_node

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
    nonce: Uint,
    balance: U256,
    code_hash: Hash32,
    storage_root: Hash32,
}
struct AddressAccountNodeDictAccess {
    key: Address,
    prev_value: AccountNode,
    new_value: AccountNode,
}

// Union of InternalNode (union type) and Extended (union type)
// Both sub unions must be inlined because of args_gen
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

// @notice Decode the RLP encoded representation of an account node.
func AccountNode_from_rlp{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    encoding: Bytes
) -> AccountNode {
    alloc_locals;

    let decoded = decode(encoding);

    let sequence = decoded.value.sequence;
    let len = sequence.value.len;
    let data = sequence.value.data;

    let nonce_bytes = data[0].value.bytes;
    let balance_bytes = data[1].value.bytes;
    let storage_root_bytes = data[2].value.bytes;
    let codehash_bytes = data[3].value.bytes;

    let balance = U256_from_be_bytes(balance_bytes);
    let codehash = Bytes_to_Bytes32(codehash_bytes);
    let nonce = Uint_from_be_bytes(nonce_bytes);
    let storage_root = Bytes_to_Bytes32(storage_root_bytes);

    tempvar res = AccountNode(
        new AccountNodeStruct(
            nonce=nonce, balance=balance, code_hash=codehash, storage_root=storage_root
        ),
    );

    return res;
}

// Process the difference between two account nodes
func _process_account_diff{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    address_preimages: MappingBytes32Address,
    main_trie_end: AddressAccountNodeDictAccess*,
}(path: Bytes32, left: OptionalLeafNode, right: OptionalLeafNode) -> () {
    alloc_locals;
    let dict_ptr = cast(address_preimages.value.dict_ptr, DictAccess*);

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let (pointer) = hashdict_read{dict_ptr=dict_ptr}(2, path.value);
    let new_dict_ptr = cast(dict_ptr, Bytes32OptionalAddressDictAccess*);
    tempvar address_preimages = MappingBytes32Address(
        new MappingBytes32AddressStruct(address_preimages.value.dict_ptr_start, new_dict_ptr)
    );
    tempvar address = Address(pointer);

    if (left.value != 0) {
        let left_decoded = AccountNode_from_rlp(left.value.value.value.bytes);
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
    } else {
        tempvar left = left;
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
    }
    let left_account = AccountNode(cast([ap - 4], AccountNodeStruct*));
    let range_check_ptr = [ap - 3];
    let bitwise_ptr = cast([ap - 2], BitwiseBuiltin*);
    let poseidon_ptr = cast([ap - 1], PoseidonBuiltin*);

    if (right.value != 0) {
        let right_decoded = AccountNode_from_rlp(right.value.value.value.bytes);
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
    } else {
        tempvar right = right;
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
    }
    let right_account = AccountNode(cast([ap - 4], AccountNodeStruct*));
    let range_check_ptr = [ap - 3];
    let bitwise_ptr = cast([ap - 2], BitwiseBuiltin*);
    let poseidon_ptr = cast([ap - 1], PoseidonBuiltin*);

    tempvar account_diff = AddressAccountNodeDictAccess(
        key=address, prev_value=left_account, new_value=right_account
    );

    assert [main_trie_end] = account_diff;
    tempvar main_trie_end = main_trie_end + AddressAccountNodeDictAccess.SIZE;
    return ();
}

// Process the difference between two storage leaf nodes
func _process_storage_diff{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    storage_key_preimages: MappingBytes32Bytes32,
    storage_trie_end: Bytes32U256DictAccess*,
}(address: Address, path: Bytes32, left: OptionalLeafNode, right: OptionalLeafNode) -> () {
    alloc_locals;
    let dict_ptr = cast(storage_key_preimages.value.dict_ptr, DictAccess*);

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let (pointer) = hashdict_read{dict_ptr=dict_ptr}(2, path.value);
    let new_dict_ptr = cast(dict_ptr, Bytes32OptionalBytes32DictAccess*);
    tempvar storage_key_preimages = MappingBytes32Bytes32(
        new MappingBytes32Bytes32Struct(storage_key_preimages.value.dict_ptr_start, new_dict_ptr)
    );
    tempvar storage_key = Bytes32(cast(pointer, Bytes32Struct*));

    if (left.value != 0) {
        let left_decoded = U256_from_rlp(left.value.value.value.bytes);
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
    } else {
        tempvar left = left;
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
    }
    let left_u256 = U256(cast([ap - 4], U256Struct*));
    let range_check_ptr = [ap - 3];
    let bitwise_ptr = cast([ap - 2], BitwiseBuiltin*);
    let poseidon_ptr = cast([ap - 1], PoseidonBuiltin*);

    if (right.value != 0) {
        let right_decoded = U256_from_rlp(right.value.value.value.bytes);
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
    } else {
        tempvar right = right;
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
    }
    let right_u256 = U256(cast([ap - 4], U256Struct*));
    let range_check_ptr = [ap - 3];
    let bitwise_ptr = cast([ap - 2], BitwiseBuiltin*);
    let poseidon_ptr = cast([ap - 1], PoseidonBuiltin*);

    let (hashed_storage_key_) = poseidon_hash_many(2, storage_key.value);
    let hashed_storage_key = HashedBytes32(hashed_storage_key_);
    tempvar account_diff = Bytes32U256DictAccess(
        key=hashed_storage_key, prev_value=left_u256, new_value=right_u256
    );

    assert [storage_trie_end] = account_diff;
    tempvar storage_trie_end = storage_trie_end + Bytes32U256DictAccess.SIZE;
    return ();
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

func resolve{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    node_store: NodeStore,
}(node: OptionalUnionInternalNodeExtended) -> OptionalInternalNode {
    alloc_locals;

    if (cast(node.value, felt) == 0) {
        let res = OptionalInternalNode(cast(0, InternalNodeEnum*));
        return res;
    }

    // Case 1: it is a node
    let is_node = cast(node.value.leaf.value, felt) + cast(node.value.extension.value, felt) + cast(
        node.value.branch.value, felt
    );
    if (is_node != 0) {
        tempvar result = OptionalInternalNode(
            new InternalNodeEnum(node.value.leaf, node.value.extension, node.value.branch)
        );
        return result;
    }

    // Case 2: it is either a node hash or an embedded node
    // Case a: it is a node hash
    if (cast(node.value.bytes.value, felt) != 0) {
        let bytes = node.value.bytes;
        if (bytes.value.len != 32) {
            // The bytes MUST be a 32-byte node hash
            raise('ValueError');
        }

        // Get the node hash from the node store
        let node_hash = Bytes_to_Bytes32(bytes);

        let result = node_store_get{poseidon_ptr=poseidon_ptr, node_store=node_store}(node_hash);

        return result;
    }

    // Case b: it is an embedded node
    if (cast(node.value.sequence.value, felt) != 0) {
        let sequence = ExtendedImpl.sequence(node.value.sequence);
        let internal_node = deserialize_to_internal_node(sequence);
        let res = OptionalInternalNode(internal_node.value);
        return res;
    }

    with_attr error_message("Value Error: No other node types are supported") {
        jmp raise.raise_label;
    }
}

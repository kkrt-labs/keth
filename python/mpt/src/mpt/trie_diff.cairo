from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import PoseidonBuiltin, BitwiseBuiltin
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.dict import DictAccess
from starkware.cairo.common.memset import memset
from starkware.cairo.common.memcpy import memcpy
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
    StringStruct,
)
from ethereum_types.numeric import U256, Uint, U256Struct, Bool, bool
from ethereum.cancun.trie import (
    LeafNode,
    LeafNodeStruct,
    ExtensionNode,
    ExtensionNodeStruct,
    BranchNode,
    BranchNodeStruct,
    Subnodes,
    SubnodesStruct,
    InternalNode,
    OptionalLeafNode,
    OptionalInternalNode,
    InternalNodeEnum,
    Bytes32U256DictAccess,
    nibble_list_to_bytes,
)
from ethereum_rlp.rlp import (
    Extended,
    ExtendedEnum,
    decode,
    U256_from_rlp,
    SequenceExtended,
    SequenceExtendedStruct,
    ExtendedImpl,
    Extended__eq__,
)

from starkware.cairo.common.builtin_poseidon.poseidon import poseidon_hash, poseidon_hash_many
from legacy.utils.dict import hashdict_read, hashdict_write, dict_new_empty, dict_read
from cairo_core.control_flow import raise
from ethereum.utils.numeric import ceil32, divmod, U256_from_be_bytes, U256_le, Uint_from_be_bytes
from ethereum.utils.bytes import (
    Bytes_to_Bytes32,
    Bytes__add__,
    Bytes__copy__,
    Bytes__eq__,
    Bytes__startswith__,
)

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
    storage_trie_end: Bytes32U256DictAccess*,
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

namespace OptionalUnionInternalNodeExtendedImpl {
    // TODO: purge if unused
    // func as_leaf(self: LeafNode) -> OptionalUnionInternalNodeExtended {
    //     return OptionalUnionInternalNodeExtended(
    //         new OptionalUnionInternalNodeExtendedEnum(
    //             leaf=self,
    //             extension=ExtensionNode(cast(0, ExtensionNodeStruct*)),
    //             branch=BranchNode(cast(0, BranchNodeStruct*)),
    //             sequence=SequenceExtended(cast(0, SequenceExtendedStruct*)),
    //             bytearray=Bytes(cast(0, BytesStruct*)),
    //             bytes=Bytes(cast(0, BytesStruct*)),
    //             uint=Uint(cast(0, UintStruct*)),
    //             fixed_uint=Uint(cast(0, UintStruct*)),
    //             str=String(cast(0, StringStruct*)),
    //             bool=Bool(cast(0, BoolStruct*)),
    //         ),
    //     );
    // }

    // func as_extension(self: ExtensionNode) -> OptionalUnionInternalNodeExtended {
    //     return OptionalUnionInternalNodeExtended(
    //         new OptionalUnionInternalNodeExtendedEnum(
    //             leaf=LeafNode(cast(0, LeafNodeStruct*)),
    //             extension=self,
    //             branch=BranchNode(cast(0, BranchNodeStruct*)),
    //             sequence=SequenceExtended(cast(0, SequenceExtendedStruct*)),
    //             bytearray=Bytes(cast(0, BytesStruct*)),
    //             bytes=Bytes(cast(0, BytesStruct*)),
    //             uint=Uint(cast(0, UintStruct*)),
    //         ),
    //     );
    // }

    // func as_branch(self: BranchNode) -> OptionalUnionInternalNodeExtended {
    //     return OptionalUnionInternalNodeExtended(
    //         new OptionalUnionInternalNodeExtendedEnum(
    //             leaf=LeafNode(cast(0, LeafNodeStruct*)),
    //             extension=ExtensionNode(cast(0, ExtensionNodeStruct*)),
    //             branch=self,
    //             sequence=SequenceExtended(cast(0, SequenceExtendedStruct*)),
    //             bytearray=Bytes(cast(0, BytesStruct*)),
    //             bytes=Bytes(cast(0, BytesStruct*)),
    //             uint=Uint(cast(0, UintStruct*)),
    //             fixed_uint=Uint(cast(0, UintStruct*)),
    //             str=String(cast(0, StringStruct*)),
    //             bool=Bool(cast(0, BoolStruct*)),
    //         ),
    //     );
    // }

    func from_leaf(self: LeafNode) -> OptionalUnionInternalNodeExtended {
        alloc_locals;
        tempvar res = OptionalUnionInternalNodeExtended(
            new OptionalUnionInternalNodeExtendedEnum(
                leaf=self,
                extension=ExtensionNode(cast(0, ExtensionNodeStruct*)),
                branch=BranchNode(cast(0, BranchNodeStruct*)),
                sequence=SequenceExtended(cast(0, SequenceExtendedStruct*)),
                bytearray=Bytes(cast(0, BytesStruct*)),
                bytes=Bytes(cast(0, BytesStruct*)),
                uint=cast(0, Uint*),
                fixed_uint=cast(0, Uint*),
                str=String(cast(0, StringStruct*)),
                bool=cast(0, Bool*),
            ),
        );
        return res;
    }

    func from_extension(self: ExtensionNode) -> OptionalUnionInternalNodeExtended {
        alloc_locals;
        tempvar res = OptionalUnionInternalNodeExtended(
            new OptionalUnionInternalNodeExtendedEnum(
                leaf=LeafNode(cast(0, LeafNodeStruct*)),
                extension=self,
                branch=BranchNode(cast(0, BranchNodeStruct*)),
                sequence=SequenceExtended(cast(0, SequenceExtendedStruct*)),
                bytearray=Bytes(cast(0, BytesStruct*)),
                bytes=Bytes(cast(0, BytesStruct*)),
                uint=cast(0, Uint*),
                fixed_uint=cast(0, Uint*),
                str=String(cast(0, StringStruct*)),
                bool=cast(0, Bool*),
            ),
        );
        return res;
    }

    func from_branch(self: BranchNode) -> OptionalUnionInternalNodeExtended {
        alloc_locals;
        tempvar res = OptionalUnionInternalNodeExtended(
            new OptionalUnionInternalNodeExtendedEnum(
                leaf=LeafNode(cast(0, LeafNodeStruct*)),
                extension=ExtensionNode(cast(0, ExtensionNodeStruct*)),
                branch=self,
                sequence=SequenceExtended(cast(0, SequenceExtendedStruct*)),
                bytearray=Bytes(cast(0, BytesStruct*)),
                bytes=Bytes(cast(0, BytesStruct*)),
                uint=cast(0, Uint*),
                fixed_uint=cast(0, Uint*),
                str=String(cast(0, StringStruct*)),
                bool=cast(0, Bool*),
            ),
        );
        return res;
    }

    func from_extended(self: Extended) -> OptionalUnionInternalNodeExtended {
        alloc_locals;
        // Input is an extended enum
        // We cast it to an enum that is simply padded by 3 (leaf, extension, branch)
        let (enum_segment) = alloc();
        memset(enum_segment, 0, InternalNodeEnum.SIZE);
        let self_ptr = cast(self.value, felt*);
        memcpy(enum_segment + InternalNodeEnum.SIZE, self_ptr, ExtendedEnum.SIZE);
        let res = OptionalUnionInternalNodeExtended(
            cast(enum_segment, OptionalUnionInternalNodeExtendedEnum*)
        );
        return res;
    }
}

// / @notice Decode the RLP encoded representation of an account node.
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

// / @notice Process the difference between two account nodes in the state trie
// / @dev Retrieves the address from preimages, decodes account data from RLP encoding,
// /      and records the difference in the main trie by writing a dict access.
// / @param path The full path to the account node in the trie
// / @param left The previous (left) account leaf node at this path
// / @param right The current (right) account leaf node at this path
func _process_account_diff{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    address_preimages: MappingBytes32Address,
    main_trie_end: AddressAccountNodeDictAccess*,
    storage_trie_end: Bytes32U256DictAccess*,
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

// / @notice Process the difference between two storage leaf nodes
// / @dev Retrieves the storage key from preimages, decodes storage values,
// /      and records the difference in the storage trie
// / @param address The account address that owns this storage
// / @param path The full path to the storage node in the trie
// / @param left The previous (left) storage leaf node at this path
// / @param right The current (right) storage leaf node at this path
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

// / @notice Recursively compute the difference between two Ethereum tries
// / @dev "Pattern matches" on node types and delegates to specialized handlers functions.
// / @param left The node from the previous state
// / @param right The node from the current state
// / @param path The path traversed so far in the trie
// / @param account_address The account address (if processing a storage trie). If processing the
// /      account trie, this is 0. If processing the storage trie, this is
// /      the address of the account that owns the storage.
func _compute_diff{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountNodeDictAccess*,
    storage_trie_end: Bytes32U256DictAccess*,
}(
    left: OptionalUnionInternalNodeExtended,
    right: OptionalUnionInternalNodeExtended,
    path: Bytes,
    account_address: Address,
) -> () {
    alloc_locals;
    // TODO: for elias?
    // we need to check whether left and right are the same, if so, no need to resolve.
    // OptionalUnionInternalNodeExtended__eq__ will need to be first doing typechecks equalities,
    // then delegate to the proper equality function of each type.
    // let is_left_eq_right = Extended__eq__(left, right);
    // if (is_left_eq_right.value != 0) {
    //     return ();
    // }

    %{ logger.debug_cairo("running _compute_diff") %}

    let l_resolved = resolve(left);
    let r_resolved = resolve(right);

    // Pattern matching on the types of left.

    // Case 1: left is null
    if (cast(l_resolved.value, felt) == 0) {
        %{ logger.debug_cairo("left is null") %}
        return _left_is_null(left, r_resolved, path, account_address);
    }

    // Case 2: left is a leaf node
    if (cast(l_resolved.value.leaf_node.value, felt) != 0) {
        %{ logger.debug_cairo("left is a leaf node") %}
        return _left_is_leaf_node(l_resolved.value.leaf_node, r_resolved, path, account_address);
    }

    // Case 3: left is an extension node
    if (cast(l_resolved.value.extension_node.value, felt) != 0) {
        %{ logger.debug_cairo("left is an extension node") %}
        return _left_is_extension_node(
            l_resolved.value.extension_node, r_resolved, path, account_address
        );
    }

    // Case 4: left is a branch node
    if (cast(l_resolved.value.branch_node.value, felt) != 0) {
        %{ logger.debug_cairo("left is a branch node") %}
        return _left_is_branch_node(
            l_resolved.value.branch_node, r_resolved, path, account_address
        );
    }

    raise('TypeError');
    return ();
}

// / @notice Handle the case when the left node is null
// / @param left The null node from the previous state
// / @param right The node from the current state
// / @param path The path traversed so far in the trie
// / @param account_address The account address (if processing a storage trie)
func _left_is_null{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountNodeDictAccess*,
    storage_trie_end: Bytes32U256DictAccess*,
}(
    left: OptionalUnionInternalNodeExtended,
    right: OptionalInternalNode,
    path: Bytes,
    account_address: Address,
) -> () {
    alloc_locals;

    // (None, None) -> pass
    if (cast(right.value, felt) == 0) {
        return ();
    }

    // (None, LeafNode()) -> new leaf
    if (cast(right.value.leaf_node.value, felt) != 0) {
        let r_leaf = right.value.leaf_node;
        let full_path_nibbles = Bytes__add__(path, r_leaf.value.rest_of_key);
        let full_path = nibble_list_to_bytes(full_path_nibbles);
        let full_path_b32 = Bytes_to_Bytes32(full_path);

        tempvar left_leaf_null = OptionalLeafNode(cast(0, LeafNodeStruct*));
        tempvar right_leaf = OptionalLeafNode(r_leaf.value);

        // Current trie is the account trie
        if (account_address.value != 0) {
            _process_account_diff(path=full_path_b32, left=left_leaf_null, right=right_leaf);
            return ();
        }

        // Current trie is the storage trie
        _process_storage_diff(
            address=account_address, path=full_path_b32, left=left_leaf_null, right=right_leaf
        );

        return ();
    }

    // (None, ExtensionNode()) -> look for diffs in the right sub-tree
    if (cast(right.value.extension_node.value, felt) != 0) {
        let r_extension = right.value.extension_node;
        let updated_path = Bytes__add__(path, r_extension.value.key_segment);
        %{ logger.debug_cairo("updated_path: %s", updated_path) %}
        let subnode = OptionalUnionInternalNodeExtendedImpl.from_extended(
            r_extension.value.subnode
        );
        return _compute_diff(
            left=left, right=subnode, path=updated_path, account_address=account_address
        );
    }

    // (None, BranchNode()) -> look for diffs in all branches of the right sub-tree
    if (cast(right.value.branch_node.value, felt) != 0) {
        _compute_left_leaf_diff_on_right_branch_node(
            left=left,
            subnodes=right.value.branch_node.value.subnodes,
            path=path,
            account_address=account_address,
            index=0,
        );
        return ();
    }

    raise('TypeError');
    return ();
}

// / @notice Handle the case when the left node is a leaf node
// / @param l_leaf The leaf node from the previous state
// / @param right The node from the current state
// / @param path The path traversed so far in the trie
// / @param account_address The account address (if processing a storage trie)
func _left_is_leaf_node{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountNodeDictAccess*,
    storage_trie_end: Bytes32U256DictAccess*,
}(l_leaf: LeafNode, right: OptionalInternalNode, path: Bytes, account_address: Address) -> () {
    alloc_locals;
    // Pattern matching on the types of right.

    // (LeafNode(), None) -> deleted leaf
    if (cast(right.value, felt) == 0) {
        let updated_path = Bytes__add__(path, l_leaf.value.rest_of_key);
        let full_path = nibble_list_to_bytes(updated_path);
        let full_path_b32 = Bytes_to_Bytes32(full_path);

        let opt_left_leaf = OptionalLeafNode(l_leaf.value);
        let right_leaf_null = OptionalLeafNode(cast(0, LeafNodeStruct*));

        if (account_address.value != 0) {
            _process_account_diff(path=full_path_b32, left=opt_left_leaf, right=right_leaf_null);
            return ();
        }

        _process_storage_diff(
            address=account_address, path=full_path_b32, left=opt_left_leaf, right=right_leaf_null
        );

        return ();
    }

    // (LeafNode(), LeafNode()) -> diffs in the leaf node
    if (cast(right.value.leaf_node.value, felt) != 0) {
        let r_leaf = right.value.leaf_node;
        let is_rest_equal = Bytes__eq__(l_leaf.value.rest_of_key, r_leaf.value.rest_of_key);

        // Same path
        if (is_rest_equal.value != 0) {
            let is_value_equal = Extended__eq__(l_leaf.value.value, r_leaf.value.value);

            // Same path + same values -> no diff
            if (is_value_equal.value != 0) {
                return ();
            }

            // Same path + different values -> updated leaf
            let updated_path = Bytes__add__(path, l_leaf.value.rest_of_key);
            let full_path = nibble_list_to_bytes(updated_path);
            let full_path_b32 = Bytes_to_Bytes32(full_path);

            let opt_left_leaf = OptionalLeafNode(l_leaf.value);
            let opt_right_leaf = OptionalLeafNode(r_leaf.value);

            if (account_address.value != 0) {
                _process_account_diff(path=full_path_b32, left=opt_left_leaf, right=opt_right_leaf);
                return ();
            }

            _process_storage_diff(
                address=account_address,
                path=full_path_b32,
                left=opt_left_leaf,
                right=opt_right_leaf,
            );

            return ();
        }

        // Different path -> deleted old leaf, create new leaf
        let updated_left_path = Bytes__add__(path, l_leaf.value.rest_of_key);
        let updated_left_path_bytes = nibble_list_to_bytes(updated_left_path);
        let updated_left_path_b32 = Bytes_to_Bytes32(updated_left_path_bytes);

        let updated_right_path = Bytes__add__(path, r_leaf.value.rest_of_key);
        let updated_right_path_nibbles = nibble_list_to_bytes(updated_right_path);
        let updated_right_path_b32 = Bytes_to_Bytes32(updated_right_path_nibbles);

        let leaf_null = OptionalLeafNode(cast(0, LeafNodeStruct*));
        let opt_right_leaf = OptionalLeafNode(r_leaf.value);
        let opt_left_leaf = OptionalLeafNode(l_leaf.value);

        if (account_address.value != 0) {
            _process_account_diff(path=updated_left_path_b32, left=opt_left_leaf, right=leaf_null);
            _process_account_diff(
                path=updated_right_path_b32, left=leaf_null, right=opt_right_leaf
            );
            return ();
        }

        _process_storage_diff(
            address=account_address, path=updated_left_path_b32, left=opt_left_leaf, right=leaf_null
        );
        _process_storage_diff(
            address=account_address,
            path=updated_right_path_b32,
            left=leaf_null,
            right=opt_right_leaf,
        );

        return ();
    }

    // (LeafNode(), ExtensionNode()) -> Explore the extension node's subtree for any new leaves,
    // comparing it to the old leaf with the same key
    if (cast(right.value.extension_node.value, felt) != 0) {
        // remove the right node's key segment from the left leaf node
        let r_extension = right.value.extension_node;
        let updated_path = Bytes__add__(path, r_extension.value.key_segment);
        %{ logger.debug_cairo("updated_path: %s", updated_path) %}
        let r_subnode = OptionalUnionInternalNodeExtendedImpl.from_extended(
            r_extension.value.subnode
        );
        // Update the left leaf node's rest of key to remove the right node's key segment
        // TODO(unsure): verify whether this is correct or if we need to use a prefix check.
        tempvar l_leaf = LeafNode(
            new LeafNodeStruct(
                rest_of_key=Bytes(
                    new BytesStruct(
                        data=l_leaf.value.rest_of_key.value.data +
                        r_extension.value.key_segment.value.len,
                        len=l_leaf.value.rest_of_key.value.len -
                        r_extension.value.key_segment.value.len,
                    ),
                ),
                value=l_leaf.value.value,
            ),
        );
        let l_leaf_typed = OptionalUnionInternalNodeExtendedImpl.from_leaf(l_leaf);
        return _compute_diff(
            left=l_leaf_typed, right=r_subnode, path=updated_path, account_address=account_address
        );
    }

    // (LeafNode(), BranchNode()) -> The branch was created and replaced the single leaf.
    // All branches - except the one whose first nibble matches the leaf's key - are new.
    // The remaining branch is compared to the leaf.
    if (cast(right.value.branch_node.value, felt) != 0) {
        let l_leaf_typed = OptionalUnionInternalNodeExtendedImpl.from_leaf(l_leaf);

        _compute_left_leaf_diff_on_right_branch_node(
            left=l_leaf_typed,
            subnodes=right.value.branch_node.value.subnodes,
            path=path,
            account_address=account_address,
            index=0,
        );
        return ();
    }

    raise('TypeError');
    return ();
}

func _left_is_extension_node{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountNodeDictAccess*,
    storage_trie_end: Bytes32U256DictAccess*,
}(left: ExtensionNode, right: OptionalInternalNode, path: Bytes, account_address: Address) -> () {
    alloc_locals;

    // (ExtensionNode(), None) -> deleted extension node
    if (cast(right.value, felt) == 0) {
        // Look for diffs in the left sub-tree
        let updated_path = Bytes__add__(path, left.value.key_segment);
        let l_subnode = OptionalUnionInternalNodeExtendedImpl.from_extended(left.value.subnode);

        let right_null = OptionalUnionInternalNodeExtended(
            cast(0, OptionalUnionInternalNodeExtendedEnum*)
        );
        return _compute_diff(
            left=l_subnode, right=right_null, path=updated_path, account_address=account_address
        );
    }

    // (ExtensionNode(), LeafNode()) -> The extension node was deleted and replaced by a leaf -
    // meaning that down the line of the extension node, in a branch, we deleted some nodes.
    // Explore the extension node's subtree for any deleted nodes, comparing it to the new leaf
    if (cast(right.value.leaf_node.value, felt) != 0) {
        // Remove the left node's key segment from the right leaf node
        let r_leaf = right.value.leaf_node;
        let updated_path = Bytes__add__(path, left.value.key_segment);
        let l_subnode = OptionalUnionInternalNodeExtendedImpl.from_extended(left.value.subnode);

        // Update the right leaf node's rest of key to remove the left node's key segment
        tempvar r_leaf = LeafNode(
            new LeafNodeStruct(
                rest_of_key=Bytes(
                    new BytesStruct(
                        data=r_leaf.value.rest_of_key.value.data + left.value.key_segment.value.len,
                        len=r_leaf.value.rest_of_key.value.len - left.value.key_segment.value.len,
                    ),
                ),
                value=r_leaf.value.value,
            ),
        );

        let r_leaf_typed = OptionalUnionInternalNodeExtendedImpl.from_leaf(r_leaf);
        return _compute_diff(
            left=l_subnode, right=r_leaf_typed, path=updated_path, account_address=account_address
        );
    }

    // (ExtensionNode(), ExtensionNode()) ->
    if (cast(right.value.extension_node.value, felt) != 0) {
        let r_extension = right.value.extension_node;
        let keys_equal = Bytes__eq__(left.value.key_segment, r_extension.value.key_segment);
        if (keys_equal.value != 0) {
            // equal keys -> look for diffs in children
            let l_subnode = OptionalUnionInternalNodeExtendedImpl.from_extended(left.value.subnode);
            let r_subnode = OptionalUnionInternalNodeExtendedImpl.from_extended(
                r_extension.value.subnode
            );
            return _compute_diff(
                left=l_subnode, right=r_subnode, path=path, account_address=account_address
            );
        }

        // Right is prefix of left
        let r_prefix_l = Bytes__startswith__(left.value.key_segment, r_extension.value.key_segment);
        if (r_prefix_l.value != 0) {
            // Compare the right node's value with the left node shortened by right key
            let updated_path = Bytes__add__(path, r_extension.value.key_segment);
            let full_path = nibble_list_to_bytes(updated_path);
            let full_path_b32 = Bytes_to_Bytes32(full_path);

            tempvar shortened_left_ext = ExtensionNode(
                new ExtensionNodeStruct(
                    key_segment=Bytes(
                        new BytesStruct(
                            data=left.value.key_segment.value.data +
                            r_extension.value.key_segment.value.len,
                            len=left.value.key_segment.value.len -
                            r_extension.value.key_segment.value.len,
                        ),
                    ),
                    subnode=left.value.subnode,
                ),
            );

            let l_ext_typed = OptionalUnionInternalNodeExtendedImpl.from_extension(
                shortened_left_ext
            );
            let r_ext_typed = OptionalUnionInternalNodeExtendedImpl.from_extension(r_extension);
            return _compute_diff(
                left=l_ext_typed,
                right=r_ext_typed,
                path=updated_path,
                account_address=account_address,
            );
        }

        // Left is prefix of right
        let l_prefix_r = Bytes__startswith__(r_extension.value.key_segment, left.value.key_segment);
        if (l_prefix_r.value != 0) {
            // Compare the left node's value with the right node shortened by left key
            let updated_path = Bytes__add__(path, left.value.key_segment);
            let full_path = nibble_list_to_bytes(updated_path);
            let full_path_b32 = Bytes_to_Bytes32(full_path);

            tempvar shortened_right_ext = ExtensionNode(
                new ExtensionNodeStruct(
                    key_segment=Bytes(
                        new BytesStruct(
                            data=r_extension.value.key_segment.value.data +
                            left.value.key_segment.value.len,
                            len=r_extension.value.key_segment.value.len -
                            left.value.key_segment.value.len,
                        ),
                    ),
                    subnode=r_extension.value.subnode,
                ),
            );

            let l_ext_typed = OptionalUnionInternalNodeExtendedImpl.from_extension(left);
            let r_ext_typed = OptionalUnionInternalNodeExtendedImpl.from_extension(
                shortened_right_ext
            );
            return _compute_diff(
                left=l_ext_typed,
                right=r_ext_typed,
                path=updated_path,
                account_address=account_address,
            );
        }

        // Both are different -> look for diffs in both sub-trees
        let null_node = OptionalUnionInternalNodeExtended(
            cast(0, OptionalUnionInternalNodeExtendedEnum*)
        );

        let l_typed = OptionalUnionInternalNodeExtendedImpl.from_extension(left);
        let updated_path_left = Bytes__add__(path, left.value.key_segment);
        _compute_diff(
            left=l_typed, right=null_node, path=updated_path_left, account_address=account_address
        );

        let r_typed = OptionalUnionInternalNodeExtendedImpl.from_extension(r_extension);
        let updated_path_right = Bytes__add__(path, r_extension.value.key_segment);
        _compute_diff(
            left=null_node, right=r_typed, path=updated_path_right, account_address=account_address
        );
        return ();
    }

    // (ExtensionNode(), BranchNode()) -> right is prefix of left
    if (cast(right.value.branch_node.value, felt) != 0) {
        let left_typed = OptionalUnionInternalNodeExtendedImpl.from_extension(left);
        _compute_left_extension_node_diff_on_right_branch_node(
            left=left_typed,
            subnodes=right.value.branch_node.value.subnodes,
            path=path,
            account_address=account_address,
            index=0,
        );
        return ();
    }

    raise('TypeError');
    return ();
}

func _left_is_branch_node{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountNodeDictAccess*,
    storage_trie_end: Bytes32U256DictAccess*,
}(left: BranchNode, right: OptionalInternalNode, path: Bytes, account_address: Address) -> () {
    alloc_locals;

    // (BranchNode(), None) -> deleted branch node
    // Look for diffs in all branches of the left sub-tree
    if (cast(right.value, felt) == 0) {
        %{ logger.debug_cairo("left is a branch node and right is null") %}
        return _compute_left_branch_on_none(
            left=left, right=right, path=path, account_address=account_address, index=0
        );
    }

    // (BranchNode(), LeafNode()) -> The branch was deleted and replaced by a single leaf.
    // All branches - except the one whose first nibble matches the leaf's key - are deleted.
    // The remaining branch is compared to the leaf.
    if (cast(right.value.leaf_node.value, felt) != 0) {
        %{ logger.debug_cairo("left is a branch node and right is a leaf node") %}
        let right_leaf = right.value.leaf_node;
        return _compute_left_branch_on_right_leaf(
            left=left, right=right_leaf, path=path, account_address=account_address, index=0
        );
    }

    // (BranchNode(), ExtensionNode()) -> Match on the corresponding nibble of the extension key
    // segment. Remove the nibble from the extension key segment and look for diffs in the
    // remaining sub-tree.
    if (cast(right.value.extension_node.value, felt) != 0) {
        %{ logger.debug_cairo("left is a branch node and right is an extension node") %}
        let right_extension = right.value.extension_node;
        return _compute_left_branch_on_right_extension_node(
            left=left, right=right_extension, path=path, account_address=account_address, index=0
        );
    }

    // (BranchNode(), BranchNode()) -> Look for diffs in all branches of the right sub-tree
    if (cast(right.value.branch_node.value, felt) != 0) {
        %{ logger.debug_cairo("left is a branch node and right is a branch node") %}
        let right_branch = right.value.branch_node;
        return _compute_left_branch_on_right_branch_node(
            left=left, right=right_branch, path=path, account_address=account_address, index=0
        );
    }

    raise('TypeError');
    return ();
}

func _compute_left_branch_on_none{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountNodeDictAccess*,
    storage_trie_end: Bytes32U256DictAccess*,
}(
    left: BranchNode,
    right: OptionalInternalNode,
    path: Bytes,
    account_address: Address,
    index: felt,
) -> () {
    alloc_locals;

    if (index == 16) {
        return ();
    }

    let subnodes_ptr = cast(left.value.subnodes.value, felt*);
    let subnode_i_extended = Extended(cast(subnodes_ptr[index], ExtendedEnum*));
    %{ logger.debug_cairo("subnode_i_extended index: %s", index) %}
    let subnode_i = OptionalUnionInternalNodeExtendedImpl.from_extended(subnode_i_extended);

    let null_node = OptionalUnionInternalNodeExtended(
        cast(0, OptionalUnionInternalNodeExtendedEnum*)
    );

    // path = path + bytes([i])
    let path_copy = Bytes__copy__(path);
    assert path_copy.value.data[path_copy.value.len] = index;
    tempvar sub_path = Bytes(
        new BytesStruct(data=path_copy.value.data, len=path_copy.value.len + 1)
    );

    return _compute_diff(
        left=null_node, right=subnode_i, path=sub_path, account_address=account_address
    );
}

func _compute_left_branch_on_right_leaf{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountNodeDictAccess*,
    storage_trie_end: Bytes32U256DictAccess*,
}(left: BranchNode, right: LeafNode, path: Bytes, account_address: Address, index: felt) -> () {
    alloc_locals;

    if (index == 16) {
        return ();
    }

    let subnodes_ptr = cast(left.value.subnodes.value, felt*);
    let subnode_i_extended = Extended(cast(subnodes_ptr[index], ExtendedEnum*));
    %{ logger.debug_cairo("subnode_i_extended index: %s", index) %}
    let subnode_i = OptionalUnionInternalNodeExtendedImpl.from_extended(subnode_i_extended);

    // path = path + bytes([i])
    let path_copy = Bytes__copy__(path);
    assert path_copy.value.data[path_copy.value.len] = index;
    tempvar sub_path = Bytes(
        new BytesStruct(data=path_copy.value.data, len=path_copy.value.len + 1)
    );

    let first_nib = right.value.rest_of_key.value.data[0];
    if (first_nib == index) {
        // Compare to the shortened leaf node
        tempvar leaf = LeafNode(
            new LeafNodeStruct(
                rest_of_key=Bytes(
                    new BytesStruct(
                        data=right.value.rest_of_key.value.data + 1,
                        len=right.value.rest_of_key.value.len - 1,
                    ),
                ),
                value=right.value.value,
            ),
        );
        let right_ = OptionalUnionInternalNodeExtendedImpl.from_leaf(leaf);
        let left_typed = OptionalUnionInternalNodeExtendedImpl.from_branch(left);
        return _compute_diff(
            left=left_typed, right=right_, path=sub_path, account_address=account_address
        );
    }
    // Compare to None
    tempvar null_node = OptionalUnionInternalNodeExtended(
        cast(0, OptionalUnionInternalNodeExtendedEnum*)
    );
    return _compute_diff(
        left=null_node, right=subnode_i, path=sub_path, account_address=account_address
    );
}

func _compute_left_branch_on_right_extension_node{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountNodeDictAccess*,
    storage_trie_end: Bytes32U256DictAccess*,
}(left: BranchNode, right: ExtensionNode, path: Bytes, account_address: Address, index: felt) -> (
    ) {
    alloc_locals;

    if (index == 16) {
        return ();
    }

    let subnodes_ptr = cast(left.value.subnodes.value, felt*);
    let subnode_i_extended = Extended(cast(subnodes_ptr[index], ExtendedEnum*));
    %{ logger.debug_cairo("subnode_i_extended index: %s", index) %}
    let subnode_i = OptionalUnionInternalNodeExtendedImpl.from_extended(subnode_i_extended);

    // path = path + bytes([i])
    let path_copy = Bytes__copy__(path);
    assert path_copy.value.data[path_copy.value.len] = index;
    tempvar sub_path = Bytes(
        new BytesStruct(data=path_copy.value.data, len=path_copy.value.len + 1)
    );

    let first_nib = right.value.key_segment.value.data[0];
    if (first_nib == index) {
        // Compare to the shortened extension node
        tempvar extension = ExtensionNode(
            new ExtensionNodeStruct(
                key_segment=Bytes(
                    new BytesStruct(
                        data=right.value.key_segment.value.data + 1,
                        len=right.value.key_segment.value.len - 1,
                    ),
                ),
                subnode=right.value.subnode,
            ),
        );
        let right_ = OptionalUnionInternalNodeExtendedImpl.from_extension(extension);
        let left_typed = OptionalUnionInternalNodeExtendedImpl.from_branch(left);
        return _compute_diff(
            left=left_typed, right=right_, path=sub_path, account_address=account_address
        );
    }
    // Compare to None
    let null_node = OptionalUnionInternalNodeExtended(
        cast(0, OptionalUnionInternalNodeExtendedEnum*)
    );
    return _compute_diff(
        left=null_node, right=subnode_i, path=sub_path, account_address=account_address
    );
}

func _compute_left_branch_on_right_branch_node{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountNodeDictAccess*,
    storage_trie_end: Bytes32U256DictAccess*,
}(left: BranchNode, right: BranchNode, path: Bytes, account_address: Address, index: felt) -> () {
    alloc_locals;

    if (index == 16) {
        return ();
    }

    let subnodes_left_ptr = cast(left.value.subnodes.value, felt*);
    let subnode_left_extended = Extended(cast(subnodes_left_ptr[index], ExtendedEnum*));
    %{ logger.debug_cairo("subnode_left_extended index: %s", ids.index) %}
    let subnode_left = OptionalUnionInternalNodeExtendedImpl.from_extended(subnode_left_extended);

    let subnodes_right_ptr = cast(right.value.subnodes.value, felt*);
    let subnode_right_extended = Extended(cast(subnodes_right_ptr[index], ExtendedEnum*));
    %{ logger.debug_cairo("subnode_right_extended index: %s", ids.index) %}
    let subnode_right = OptionalUnionInternalNodeExtendedImpl.from_extended(subnode_right_extended);

    // path = path + bytes([i])
    let path_copy = Bytes__copy__(path);
    assert path_copy.value.data[path_copy.value.len] = index;
    tempvar sub_path = Bytes(
        new BytesStruct(data=path_copy.value.data, len=path_copy.value.len + 1)
    );

    return _compute_diff(
        left=subnode_left, right=subnode_right, path=sub_path, account_address=account_address
    );
}

// TODO: the none case could be split out.
// / @notice Process differences in all branches of the right branch node
// / @dev Recursively processes each branch with index 0-15
// / @param left The Optional Leaf Node from the previous state
// / @param subnodes The subnodes of the right branch node
// / @param path The path traversed so far in the trie
// / @param account_address The account address (if processing a storage trie)
// / @param index The current branch index being processed (0-15)
func _compute_left_leaf_diff_on_right_branch_node{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountNodeDictAccess*,
    storage_trie_end: Bytes32U256DictAccess*,
}(
    left: OptionalUnionInternalNodeExtended,
    subnodes: Subnodes,
    path: Bytes,
    account_address: Address,
    index: felt,
) -> () {
    alloc_locals;

    if (index == 16) {
        return ();
    }

    // Use `branch_0` as the base pointer to the list of subnodes and index it as a felt*.
    let subnodes_ptr = cast(subnodes.value, felt*);
    let subnode_i_extended = Extended(cast(subnodes_ptr[index], ExtendedEnum*));
    %{ logger.debug_cairo("subnode_i_extended index: %s", index) %}
    let subnode_i = OptionalUnionInternalNodeExtendedImpl.from_extended(subnode_i_extended);

    // TODO: optimization possible here

    // path = path + bytes([i])
    let path_copy = Bytes__copy__(path);
    assert path_copy.value.data[path_copy.value.len] = index;
    tempvar sub_path = Bytes(
        new BytesStruct(data=path_copy.value.data, len=path_copy.value.len + 1)
    );

    // Three cases:
    // 1. The first nibble of the subnode matches the branch node's key segment, in which
    // case we compare to the leaf node shortened by the nibble,
    // 2. It doesn't in which case we compare to None.
    // 3. The leaf is None. (see 2.)

    if (cast(left.value, felt) == 0) {
        // None leaf
        tempvar left = left;
    } else {
        // Leaf node
        let l_leaf = left.value.leaf;
        let first_nib = l_leaf.value.rest_of_key.value.data[0];
        if (first_nib == index) {
            // Compare to the shortened leaf node
            tempvar leaf = LeafNode(
                new LeafNodeStruct(
                    rest_of_key=Bytes(
                        new BytesStruct(
                            data=l_leaf.value.rest_of_key.value.data + 1,
                            len=l_leaf.value.rest_of_key.value.len - 1,
                        ),
                    ),
                    value=l_leaf.value.value,
                ),
            );
            let left_ = OptionalUnionInternalNodeExtendedImpl.from_leaf(l_leaf);
            tempvar left = left_;
        } else {
            // Compare to None
            tempvar left = OptionalUnionInternalNodeExtended(
                cast(0, OptionalUnionInternalNodeExtendedEnum*)
            );
        }
    }
    let left = OptionalUnionInternalNodeExtended(
        cast([ap - 1], OptionalUnionInternalNodeExtendedEnum*)
    );

    _compute_diff(left=left, right=subnode_i, path=sub_path, account_address=account_address);

    return _compute_left_leaf_diff_on_right_branch_node(
        left=left,
        subnodes=subnodes,
        path=sub_path,
        account_address=account_address,
        index=index + 1,
    );
}

// TODO left should not be optional
func _compute_left_extension_node_diff_on_right_branch_node{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountNodeDictAccess*,
    storage_trie_end: Bytes32U256DictAccess*,
}(
    left: OptionalUnionInternalNodeExtended,
    subnodes: Subnodes,
    path: Bytes,
    account_address: Address,
    index: felt,
) -> () {
    alloc_locals;
    if (index == 16) {
        return ();
    }

    // Use `branch_0` as the base pointer to the list of subnodes and index it as a felt*.
    let subnodes_ptr = cast(subnodes.value, felt*);
    let subnode_i_extended = Extended(cast(subnodes_ptr[index], ExtendedEnum*));
    %{ logger.debug_cairo("subnode_i_extended index: %s", index) %}
    let subnode_i = OptionalUnionInternalNodeExtendedImpl.from_extended(subnode_i_extended);

    // TODO: optimization possible here

    // path = path + bytes([i])
    let path_copy = Bytes__copy__(path);
    assert path_copy.value.data[path_copy.value.len] = index;
    tempvar sub_path = Bytes(
        new BytesStruct(data=path_copy.value.data, len=path_copy.value.len + 1)
    );

    // Two cases:
    // 1. The first nibble of the subnode matches the branch node's key segment, in which
    // case we compare to the leaf node shortened by the nibble,
    // 2. It doesn't in which case we compare to None.

    // Leaf node
    let l_extension = left.value.extension;
    let first_nib = l_extension.value.key_segment.value.data[0];
    if (first_nib == index) {
        // Compare to the shortened extension node
        tempvar extension = ExtensionNode(
            new ExtensionNodeStruct(
                key_segment=Bytes(
                    new BytesStruct(
                        data=l_extension.value.key_segment.value.data + 1,
                        len=l_extension.value.key_segment.value.len - 1,
                    ),
                ),
                subnode=l_extension.value.subnode,
            ),
        );
        let left_ = OptionalUnionInternalNodeExtendedImpl.from_extension(l_extension);
        tempvar left = left_;
    } else {
        // Compare to None
        tempvar left = OptionalUnionInternalNodeExtended(
            cast(0, OptionalUnionInternalNodeExtendedEnum*)
        );
    }
    let left = OptionalUnionInternalNodeExtended(
        cast([ap - 1], OptionalUnionInternalNodeExtendedEnum*)
    );

    _compute_diff(left=left, right=subnode_i, path=sub_path, account_address=account_address);

    return _compute_left_extension_node_diff_on_right_branch_node(
        left=left,
        subnodes=subnodes,
        path=sub_path,
        account_address=account_address,
        index=index + 1,
    );
}

// / @notice Retrieve a node from the node store by its hash
// / @dev Uses the poseidon hash as key to look up the node
// / @param node_hash The hash of the node to retrieve
// / @return The retrieved node or null if not found
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

// / @notice Resolve an OptionalUnionInternalNodeExtended to an OptionalInternalNode
// / @dev Handles various node references including direct nodes, hashed nodes, and embedded nodes
// / @param node The node to resolve
// / @return The resolved internal node
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
    // Case 2.a: it is a node hash or null
    if (cast(node.value.bytes.value, felt) != 0) {
        let bytes = node.value.bytes;
        // Case 2.a.1: it is an empty subnode
        if (bytes.value.len == 0) {
            let res = OptionalInternalNode(cast(0, InternalNodeEnum*));
            return res;
        }

        // Case 2.a.2: it is a 32-byte node hash
        if (bytes.value.len != 32) {
            // The bytes MUST be a 32-byte node hash
            raise('ValueError');
        }

        // Get the node hash from the node store
        let node_hash = Bytes_to_Bytes32(bytes);

        let result = node_store_get{poseidon_ptr=poseidon_ptr, node_store=node_store}(node_hash);

        return result;
    }

    // Case 2.b: it is an embedded node
    if (cast(node.value.sequence.value, felt) != 0) {
        let sequence = ExtendedImpl.sequence(node.value.sequence);
        let internal_node = deserialize_to_internal_node(sequence);
        tempvar res = OptionalInternalNode(internal_node.value);
        return res;
    }

    with_attr error_message("ValueError") {
        jmp raise.raise_label;
    }
}

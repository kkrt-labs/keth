from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import PoseidonBuiltin, BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.builtin_keccak.keccak import keccak_uint256s
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.dict import DictAccess
from starkware.cairo.common.memset import memset
from starkware.cairo.common.memcpy import memcpy
from ethereum.crypto.hash import Hash32, keccak256
from ethereum.cancun.fork_types import (
    OptionalAddress,
    Address,
    Account,
    AccountStruct,
    OptionalAccount,
    TupleAddressBytes32U256DictAccess,
    HashedTupleAddressBytes32,
)
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
from ethereum.utils.bytes import Bytes20_to_Bytes, Bytes32_to_Bytes
from ethereum_types.numeric import U256, Uint, U256Struct, Bool, bool
from ethereum.cancun.trie import (
    LeafNode,
    LeafNodeStruct,
    LeafNode__eq__,
    ExtensionNode,
    ExtensionNodeStruct,
    ExtensionNode__eq__,
    BranchNode,
    BranchNodeStruct,
    BranchNode__eq__,
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
    Account_from_rlp,
    Extended,
    ExtendedEnum,
    decode,
    U256_from_rlp,
    SequenceExtended,
    SequenceExtendedStruct,
    ExtendedImpl,
    Extended__eq__,
    SequenceExtended__eq__,
)

from starkware.cairo.common.builtin_poseidon.poseidon import poseidon_hash, poseidon_hash_many
from legacy.utils.bytes import felt_to_bytes20_little
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

from mpt.utils import (
    deserialize_to_internal_node,
    check_branch_node,
    check_leaf_node,
    check_extension_node,
    decode_to_internal_node,
)
from mpt.types import (
    NodeStore,
    NodeStoreStruct,
    NodeStoreDictAccess,
    MappingBytes32Address,
    MappingBytes32AddressStruct,
    Bytes32OptionalAddressDictAccess,
    MappingBytes32Bytes32,
    MappingBytes32Bytes32Struct,
    Bytes32Bytes32DictAccess,
    AccountDiff,
    AccountDiffStruct,
    StorageDiff,
    StorageDiffStruct,
    StorageDiffEntry,
    StorageDiffEntryStruct,
    AddressAccountDiffEntryStruct,
    AddressAccountDiffEntry,
    OptionalUnionInternalNodeExtended,
    OptionalUnionInternalNodeExtendedEnum,
)

const EMPTY_TRIE_HASH_LOW = 0x6ef8c092e64583ffa655cc1b171fe856;
const EMPTY_TRIE_HASH_HIGH = 0x21b463e3b52f6201c0ad6c991be0485b;

// / @notice Implementation details for OptionalUnionInternalNodeExtended.
namespace OptionalUnionInternalNodeExtendedImpl {
    // @notice Creates an OptionalUnionInternalNodeExtended from a LeafNode.
    // @param self The LeafNode to wrap.
    // @return The OptionalUnionInternalNodeExtended containing the LeafNode.
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

    // @notice Creates an OptionalUnionInternalNodeExtended from an ExtensionNode.
    // @param self The ExtensionNode to wrap.
    // @return The OptionalUnionInternalNodeExtended containing the ExtensionNode.
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

    // @notice Creates an OptionalUnionInternalNodeExtended from a BranchNode.
    // @param self The BranchNode to wrap.
    // @return The OptionalUnionInternalNodeExtended containing the BranchNode.
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

    // @notice Creates an OptionalUnionInternalNodeExtended from an Extended type.
    // @dev Casts the Extended enum to the padded OptionalUnionInternalNodeExtendedEnum.
    // @param self The Extended value to wrap.
    // @return The OptionalUnionInternalNodeExtended containing the Extended value.
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

// @notice Compares two OptionalUnionInternalNodeExtended instances for equality.
// @dev Handles null checks, type checks for InternalNode variants (Leaf, Extension, Branch),
//      and delegates to Extended__eq__ for Extended types.
// @param left The left OptionalUnionInternalNodeExtended instance.
// @param right The right OptionalUnionInternalNodeExtended instance.
// @return bool(1) if equal, bool(0) otherwise.
func OptionalUnionInternalNodeExtended__eq__(
    left: OptionalUnionInternalNodeExtended, right: OptionalUnionInternalNodeExtended
) -> bool {
    // Type checks

    // Null checks
    if (cast(left.value, felt) == 0) {
        if (cast(right.value, felt) == 0) {
            let res = bool(1);
            return res;
        }
        let res = bool(0);
        return res;
    }
    // Left is non-null, right is null -> different types
    if (cast(right.value, felt) == 0) {
        let res = bool(0);
        return res;
    }

    // # InternalNode checks

    // Leaf checks
    if (cast(left.value.leaf.value, felt) != 0) {
        if (cast(right.value.leaf.value, felt) != 0) {
            let leaf_eq = LeafNode__eq__(left.value.leaf, right.value.leaf);
            return leaf_eq;
        }
        let res = bool(0);
        return res;
    }
    if (cast(right.value.leaf.value, felt) != 0) {
        let res = bool(0);
        return res;
    }

    if (cast(left.value.extension.value, felt) != 0) {
        if (cast(right.value.extension.value, felt) != 0) {
            let extension_eq = ExtensionNode__eq__(left.value.extension, right.value.extension);
            return extension_eq;
        }
        let res = bool(0);
        return res;
    }
    if (cast(right.value.extension.value, felt) != 0) {
        let res = bool(0);
        return res;
    }

    if (cast(left.value.branch.value, felt) != 0) {
        if (cast(right.value.branch.value, felt) != 0) {
            let branch_eq = BranchNode__eq__(left.value.branch, right.value.branch);
            return branch_eq;
        }
        let res = bool(0);
        return res;
    }
    if (cast(right.value.branch.value, felt) != 0) {
        let res = bool(0);
        return res;
    }

    // # Extended checks
    // # Because we know we're not an InternalNode (nor None, we checked types for left and right),
    // we can delegate this to Extended__eq__ we can simply cast the sequence pointer (first variant
    // of the ExtendedEnum) to an ExtendedEnum*
    let left_extended_ptr = cast(left.value + InternalNodeEnum.SIZE, ExtendedEnum*);
    let left_extended = Extended(left_extended_ptr);
    let right_extended_ptr = cast(right.value + InternalNodeEnum.SIZE, ExtendedEnum*);
    let right_extended = Extended(right_extended_ptr);
    let res = Extended__eq__(left_extended, right_extended);
    return res;
}

// @notice Processes the difference between two account nodes in the state trie.
// @dev Retrieves the address from preimages using the path hash, decodes account data from
//      RLP encoding for both left and right nodes, records the difference in the
//      `main_trie_end` structure, and recursively calls `_compute_diff` for the storage trie.
// @implicit node_store Access to the global node store for resolving hashes.
// @implicit address_preimages Mapping from path hash to account address.
// @implicit storage_key_preimages Mapping from storage key hash to storage key (passed down).
// @implicit main_trie_end Pointer to the current end of the account diff list.
// @implicit storage_tries_end Pointer to the current end of the storage diff list (passed down).
// @param path The keccak hash of the account address (path in the state trie).
// @param left The previous (left) account leaf node at this path (optional).
// @param right The current (right) account leaf node at this path (optional).
// @return Updates main_trie_end and potentially storage_tries_end via recursive calls.
func _process_account_diff{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountDiffEntry*,
    storage_tries_end: StorageDiffEntry*,
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

    // INVARIANT [Soundness]: check keccak(address) == path
    let address_bytes = Bytes20_to_Bytes(address);
    let hashed_address = keccak256(address_bytes);
    with_attr error_message("INVARIANT - Invalid address preimage: keccak(address) != path") {
        assert hashed_address.value.low = path.value.low;
        assert hashed_address.value.high = path.value.high;
    }

    if (left.value != 0) {
        let (left_account, left_storage_root_bytes) = Account_from_rlp(
            left.value.value.value.bytes
        );
        let left_storage_root_extended = ExtendedImpl.bytes(left_storage_root_bytes);
        let left_storage_root = OptionalUnionInternalNodeExtendedImpl.from_extended(
            left_storage_root_extended
        );
        tempvar left_storage_root = left_storage_root;
        tempvar left_optional_account = OptionalAccount(left_account.value);
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar keccak_ptr = keccak_ptr;
    } else {
        tempvar left_storage_root = OptionalUnionInternalNodeExtended(
            cast(0, OptionalUnionInternalNodeExtendedEnum*)
        );
        tempvar left = left;
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar keccak_ptr = keccak_ptr;
    }
    let left_storage_root = OptionalUnionInternalNodeExtended(
        cast([ap - 6], OptionalUnionInternalNodeExtendedEnum*)
    );
    let left_optional_account = OptionalAccount(cast([ap - 5], AccountStruct*));
    let range_check_ptr = [ap - 4];
    let bitwise_ptr = cast([ap - 3], BitwiseBuiltin*);
    let poseidon_ptr = cast([ap - 2], PoseidonBuiltin*);
    let keccak_ptr = cast([ap - 1], KeccakBuiltin*);

    if (right.value != 0) {
        let (right_account, right_storage_root_bytes) = Account_from_rlp(
            right.value.value.value.bytes
        );

        let right_storage_root_extended = ExtendedImpl.bytes(right_storage_root_bytes);
        let right_storage_root = OptionalUnionInternalNodeExtendedImpl.from_extended(
            right_storage_root_extended
        );
        tempvar right_storage_root = right_storage_root;
        tempvar right_account = right_account;
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar keccak_ptr = keccak_ptr;
    } else {
        tempvar right_storage_root = OptionalUnionInternalNodeExtended(
            cast(0, OptionalUnionInternalNodeExtendedEnum*)
        );
        tempvar right = right;
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar keccak_ptr = keccak_ptr;
    }
    let right_storage_root = OptionalUnionInternalNodeExtended(
        cast([ap - 6], OptionalUnionInternalNodeExtendedEnum*)
    );
    let right_account = Account(cast([ap - 5], AccountStruct*));
    let range_check_ptr = [ap - 4];
    let bitwise_ptr = cast([ap - 3], BitwiseBuiltin*);
    let poseidon_ptr = cast([ap - 2], PoseidonBuiltin*);
    let keccak_ptr = cast([ap - 1], KeccakBuiltin*);
    tempvar account_diff = AddressAccountDiffEntry(
        new AddressAccountDiffEntryStruct(
            key=address, prev_value=left_optional_account, new_value=right_account
        ),
    );

    assert [main_trie_end] = account_diff;
    tempvar main_trie_end = main_trie_end + AddressAccountDiffEntry.SIZE;

    let (new_path_buffer) = alloc();
    tempvar new_path = Bytes(new BytesStruct(new_path_buffer, 0));

    tempvar new_address = OptionalAddress(new address.value);

    _compute_diff(
        left=left_storage_root, right=right_storage_root, path=new_path, account_address=new_address
    );
    return ();
}

// @notice Processes the difference between two storage leaf nodes for a specific account.
// @dev Retrieves the storage key from preimages using the path hash, decodes storage values
//      (U256) from RLP encoding for both left and right nodes, and records the difference
//      in the `storage_tries_end` structure.
// @implicit storage_key_preimages Mapping from storage path hash to storage key.
// @implicit storage_tries_end Pointer to the current end of the storage diff list.
// @param address The account address that owns this storage trie.
// @param path The keccak hash of the storage key (path in the storage trie).
// @param left The previous (left) storage leaf node at this path (optional).
// @param right The current (right) storage leaf node at this path (optional).
// @return Updates storage_tries_end.
func _process_storage_diff{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    storage_key_preimages: MappingBytes32Bytes32,
    storage_tries_end: StorageDiffEntry*,
}(address: Address, path: Bytes32, left: OptionalLeafNode, right: OptionalLeafNode) -> () {
    alloc_locals;
    let dict_ptr = cast(storage_key_preimages.value.dict_ptr, DictAccess*);

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let (pointer) = hashdict_read{dict_ptr=dict_ptr}(2, path.value);
    let new_dict_ptr = cast(dict_ptr, Bytes32Bytes32DictAccess*);
    tempvar storage_key_preimages = MappingBytes32Bytes32(
        new MappingBytes32Bytes32Struct(storage_key_preimages.value.dict_ptr_start, new_dict_ptr)
    );
    tempvar storage_key = Bytes32(cast(pointer, Bytes32Struct*));

    // INVARIANT [Soundness]: check keccak(storage_key) == path
    let (storage_key_hash) = keccak_uint256s(1, storage_key.value);
    with_attr error_message(
            "INVARIANT - Invalid storage key preimage: keccak(storage_key) != path") {
        assert storage_key_hash.low = path.value.low;
        assert storage_key_hash.high = path.value.high;
    }

    if (left.value != 0) {
        let left_decoded = U256_from_rlp(left.value.value.value.bytes);
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar keccak_ptr = keccak_ptr;
    } else {
        tempvar left = left;
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar keccak_ptr = keccak_ptr;
    }

    let left_u256 = U256(cast([ap - 5], U256Struct*));
    let range_check_ptr = [ap - 4];
    let bitwise_ptr = cast([ap - 3], BitwiseBuiltin*);
    let poseidon_ptr = cast([ap - 2], PoseidonBuiltin*);
    let keccak_ptr = cast([ap - 1], KeccakBuiltin*);

    if (right.value != 0) {
        let right_decoded = U256_from_rlp(right.value.value.value.bytes);
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar keccak_ptr = keccak_ptr;
    } else {
        tempvar right = right;
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar keccak_ptr = keccak_ptr;
    }
    let right_u256 = U256(cast([ap - 5], U256Struct*));
    let range_check_ptr = [ap - 4];
    let bitwise_ptr = cast([ap - 3], BitwiseBuiltin*);
    let poseidon_ptr = cast([ap - 2], PoseidonBuiltin*);
    let keccak_ptr = cast([ap - 1], KeccakBuiltin*);

    let (tuple_address_bytes32_buffer) = alloc();
    assert [tuple_address_bytes32_buffer] = address.value;
    assert [tuple_address_bytes32_buffer + 1] = storage_key.value.low;
    assert [tuple_address_bytes32_buffer + 2] = storage_key.value.high;
    let (hashed_storage_key_) = poseidon_hash_many(3, tuple_address_bytes32_buffer);
    let hashed_storage_key = HashedTupleAddressBytes32(hashed_storage_key_);
    tempvar storage_diff_entry = StorageDiffEntry(
        new StorageDiffEntryStruct(
            key=hashed_storage_key, prev_value=left_u256, new_value=right_u256
        ),
    );

    assert [storage_tries_end] = storage_diff_entry;
    tempvar storage_tries_end = storage_tries_end + StorageDiffEntry.SIZE;
    return ();
}

// @notice Entry point for computing the difference between two Ethereum tries (state or storage).
// @dev Initializes diff lists, calls the recursive `_compute_diff` function, and returns the
//      collected account and storage differences.
// @param node_store The initial node store containing MPT nodes.
// @param address_preimages Mapping from path hash to account address preimages.
// @param storage_key_preimages Mapping from storage path hash to storage key preimages.
// @param left The root node (or reference) of the previous state trie.
// @param right The root node (or reference) of the current state trie.
// @return account_diff A list containing differences found in account nodes.
// @return storage_diff A list containing differences found in storage nodes across all accounts.
func compute_diff_entrypoint{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}(
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    left: OptionalUnionInternalNodeExtended,
    right: OptionalUnionInternalNodeExtended,
) -> (AccountDiff, StorageDiff) {
    alloc_locals;
    let (main_trie_end: AddressAccountDiffEntry*) = alloc();

    local main_trie_start: AddressAccountDiffEntry* = main_trie_end;

    let (storage_tries_end: StorageDiffEntry*) = alloc();
    let storage_tries_start = storage_tries_end;

    tempvar account_address = OptionalAddress(cast(0, felt*));
    let (buffer) = alloc();
    tempvar path = Bytes(new BytesStruct(buffer, 0));

    _compute_diff{
        node_store=node_store,
        address_preimages=address_preimages,
        storage_key_preimages=storage_key_preimages,
        main_trie_end=main_trie_end,
        storage_tries_end=storage_tries_end,
    }(left=left, right=right, path=path, account_address=account_address);

    tempvar account_diff = AccountDiff(
        new AccountDiffStruct(data=main_trie_start, len=main_trie_end - main_trie_start)
    );
    tempvar storage_diff = StorageDiff(
        new StorageDiffStruct(data=storage_tries_start, len=storage_tries_end - storage_tries_start)
    );

    return (account_diff, storage_diff);
}

// @notice Recursively computes the difference between two Ethereum tries (or sub-tries).
// @dev Resolves node references (hashes), pattern matches on the types of the left and right
//      nodes, and delegates to specialized handler functions (`_left_is_null`,
//      `_left_is_leaf_node`, etc.) to process the differences based on the node type
//      combinations. Handles the base case where left and right nodes are identical.
// @implicit node_store Passed down for node resolution.
// @implicit address_preimages Passed down for account processing.
// @implicit storage_key_preimages Passed down for storage processing.
// @implicit main_trie_end Passed down to record account diffs.
// @implicit storage_tries_end Passed down to record storage diffs.
// @param left The node (or reference) from the previous state's trie.
// @param right The node (or reference) from the current state's trie.
// @param path The path (sequence of nibbles) traversed so far in the trie.
// @param account_address The account address if processing a storage trie, otherwise 0.
// @return Recursively updates diff lists via helper functions.
func _compute_diff{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountDiffEntry*,
    storage_tries_end: StorageDiffEntry*,
}(
    left: OptionalUnionInternalNodeExtended,
    right: OptionalUnionInternalNodeExtended,
    path: Bytes,
    account_address: OptionalAddress,
) -> () {
    alloc_locals;

    let is_left_eq_right = OptionalUnionInternalNodeExtended__eq__(left, right);
    if (is_left_eq_right.value != 0) {
        return ();
    }

    let l_resolved = resolve(left);
    let r_resolved = resolve(right);

    // Pattern matching on the types of left.

    // Case 1: left is null
    if (cast(l_resolved.value, felt) == 0) {
        return _left_is_null(left, r_resolved, path, account_address);
    }

    // Case 2: left is a leaf node
    if (cast(l_resolved.value.leaf_node.value, felt) != 0) {
        return _left_is_leaf_node(l_resolved.value.leaf_node, r_resolved, path, account_address);
    }

    // Case 3: left is an extension node
    if (cast(l_resolved.value.extension_node.value, felt) != 0) {
        return _left_is_extension_node(
            l_resolved.value.extension_node, r_resolved, path, account_address
        );
    }

    // Case 4: left is a branch node
    if (cast(l_resolved.value.branch_node.value, felt) != 0) {
        return _left_is_branch_node(
            l_resolved.value.branch_node, r_resolved, path, account_address
        );
    }

    with_attr error_message("TypeError") {
        jmp raise.raise_label;
    }
}

// @notice Handles the diff computation case where the left node is null.
// @dev Compares a null left node with the resolved right node (Leaf, Extension, Branch, or Null).
//      If right is Leaf, logs a new leaf creation. If right is Extension or Branch,
//      recursively calls `_compute_diff` on the right sub-tree with a null left node.
// @implicit node_store Passed down.
// @implicit address_preimages Passed down.
// @implicit storage_key_preimages Passed down.
// @implicit main_trie_end Passed down.
// @implicit storage_tries_end Passed down.
// @param left The null node from the previous state (represented as OptionalUnionInternalNodeExtended).
// @param right The resolved node from the current state (OptionalInternalNode).
// @param path The path traversed so far.
// @param account_address The current account address (0 for state trie).
// @return Updates diff lists based on the type of the right node.
func _left_is_null{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountDiffEntry*,
    storage_tries_end: StorageDiffEntry*,
}(
    left: OptionalUnionInternalNodeExtended,
    right: OptionalInternalNode,
    path: Bytes,
    account_address: OptionalAddress,
) -> () {
    alloc_locals;

    // (None, None) -> pass
    if (cast(right.value, felt) == 0) {
        return ();
    }

    // (None, LeafNode()) -> new leaf
    if (cast(right.value.leaf_node.value, felt) != 0) {
        let r_leaf = right.value.leaf_node;
        check_leaf_node(path, r_leaf);
        let full_path_nibbles = Bytes__add__(path, r_leaf.value.rest_of_key);
        let full_path = nibble_list_to_bytes(full_path_nibbles);
        let full_path_b32 = Bytes_to_Bytes32(full_path);

        tempvar left_leaf_null = OptionalLeafNode(cast(0, LeafNodeStruct*));
        tempvar right_leaf = OptionalLeafNode(r_leaf.value);

        // Current trie is the account trie
        if (account_address.value == 0) {
            _process_account_diff(path=full_path_b32, left=left_leaf_null, right=right_leaf);
            return ();
        }

        // Current trie is the storage trie
        _process_storage_diff(
            address=Address([account_address.value]),
            path=full_path_b32,
            left=left_leaf_null,
            right=right_leaf,
        );

        return ();
    }

    // (None, ExtensionNode()) -> look for diffs in the right sub-tree
    if (cast(right.value.extension_node.value, felt) != 0) {
        let r_extension = right.value.extension_node;
        check_extension_node(r_extension);
        let updated_path = Bytes__add__(path, r_extension.value.key_segment);
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

// @notice Handles the diff computation case where the left node is a LeafNode.
// @dev Compares the left LeafNode with the resolved right node (Null, Leaf, Extension, or Branch).
//      Handles leaf deletion, update, path change, and replacement by Extension/Branch nodes.
// @implicit node_store Passed down.
// @implicit address_preimages Passed down.
// @implicit storage_key_preimages Passed down.
// @implicit main_trie_end Passed down.
// @implicit storage_tries_end Passed down.
// @param l_leaf The LeafNode from the previous state.
// @param right The resolved node from the current state (OptionalInternalNode).
// @param path The path traversed so far.
// @param account_address The current account address (0 for state trie).
// @return Updates diff lists based on the comparison results.
func _left_is_leaf_node{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountDiffEntry*,
    storage_tries_end: StorageDiffEntry*,
}(l_leaf: LeafNode, right: OptionalInternalNode, path: Bytes, account_address: OptionalAddress) -> (
    ) {
    alloc_locals;
    // Pattern matching on the types of right.

    check_leaf_node(path, l_leaf);

    // (LeafNode(), None) -> deleted leaf
    if (cast(right.value, felt) == 0) {
        let updated_path = Bytes__add__(path, l_leaf.value.rest_of_key);
        let full_path = nibble_list_to_bytes(updated_path);
        let full_path_b32 = Bytes_to_Bytes32(full_path);

        let opt_left_leaf = OptionalLeafNode(l_leaf.value);
        let right_leaf_null = OptionalLeafNode(cast(0, LeafNodeStruct*));

        if (account_address.value == 0) {
            _process_account_diff(path=full_path_b32, left=opt_left_leaf, right=right_leaf_null);
            return ();
        }

        _process_storage_diff(
            address=Address([account_address.value]),
            path=full_path_b32,
            left=opt_left_leaf,
            right=right_leaf_null,
        );

        return ();
    }

    // (LeafNode(), LeafNode()) -> diffs in the leaf node
    if (cast(right.value.leaf_node.value, felt) != 0) {
        let r_leaf = right.value.leaf_node;
        check_leaf_node(path, r_leaf);
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

            if (account_address.value == 0) {
                _process_account_diff(path=full_path_b32, left=opt_left_leaf, right=opt_right_leaf);
                return ();
            }

            _process_storage_diff(
                address=Address([account_address.value]),
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
        let updated_right_path_bytes = nibble_list_to_bytes(updated_right_path);
        let updated_right_path_b32 = Bytes_to_Bytes32(updated_right_path_bytes);

        let leaf_null = OptionalLeafNode(cast(0, LeafNodeStruct*));
        let opt_right_leaf = OptionalLeafNode(r_leaf.value);
        let opt_left_leaf = OptionalLeafNode(l_leaf.value);

        if (account_address.value == 0) {
            _process_account_diff(path=updated_left_path_b32, left=opt_left_leaf, right=leaf_null);
            _process_account_diff(
                path=updated_right_path_b32, left=leaf_null, right=opt_right_leaf
            );
            return ();
        }

        _process_storage_diff(
            address=Address([account_address.value]),
            path=updated_left_path_b32,
            left=opt_left_leaf,
            right=leaf_null,
        );
        _process_storage_diff(
            address=Address([account_address.value]),
            path=updated_right_path_b32,
            left=leaf_null,
            right=opt_right_leaf,
        );

        return ();
    }

    // (LeafNode(), ExtensionNode()) -> Explore the extension node's subtree for any new leaves,
    // comparing it to the old leaf with the same key
    if (cast(right.value.extension_node.value, felt) != 0) {
        let r_extension = right.value.extension_node;
        check_extension_node(r_extension);
        let r_prefix_l = Bytes__startswith__(
            l_leaf.value.rest_of_key, r_extension.value.key_segment
        );
        if (r_prefix_l.value != 0) {
            let updated_path = Bytes__add__(path, r_extension.value.key_segment);
            let r_subnode = OptionalUnionInternalNodeExtendedImpl.from_extended(
                r_extension.value.subnode
            );
            // Update the left leaf node's rest of key to remove the right node's key segment
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
                left=l_leaf_typed,
                right=r_subnode,
                path=updated_path,
                account_address=account_address,
            );
        }
        // else, the left leaf node is not a prefix of the right extension node
        // we compare left with none and none with right
        let null_node = OptionalUnionInternalNodeExtended(
            cast(0, OptionalUnionInternalNodeExtendedEnum*)
        );

        // Compute diffs in the right sub-tree
        let updated_path_right = Bytes__add__(path, r_extension.value.key_segment);
        let r_subnode = OptionalUnionInternalNodeExtendedImpl.from_extended(
            r_extension.value.subnode
        );

        _compute_diff(
            left=null_node,
            right=r_subnode,
            path=updated_path_right,
            account_address=account_address,
        );

        // Compute deletions in the left sub-tree
        let updated_path_left = Bytes__add__(path, l_leaf.value.rest_of_key);
        let updated_path_left_nibbles = nibble_list_to_bytes(updated_path_left);
        let updated_path_left_b32 = Bytes_to_Bytes32(updated_path_left_nibbles);
        let opt_left_leaf = OptionalLeafNode(l_leaf.value);
        let opt_right_leaf = OptionalLeafNode(cast(0, LeafNodeStruct*));

        if (account_address.value == 0) {
            _process_account_diff(
                path=updated_path_left_b32, left=opt_left_leaf, right=opt_right_leaf
            );
            return ();
        }

        _process_storage_diff(
            address=Address([account_address.value]),
            path=updated_path_left_b32,
            left=opt_left_leaf,
            right=opt_right_leaf,
        );

        return ();
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

    with_attr error_message("TypeError") {
        jmp raise.raise_label;
    }
}

// @notice Handles the diff computation case where the left node is an ExtensionNode.
// @dev Compares the left ExtensionNode with the resolved right node (Null, Leaf, Extension, Branch).
//      Handles extension deletion, replacement by Leaf, modifications (key changes, subnode changes),
//      and replacement by Branch nodes. Considers prefix relationships between keys.
// @implicit node_store Passed down.
// @implicit address_preimages Passed down.
// @implicit storage_key_preimages Passed down.
// @implicit main_trie_end Passed down.
// @implicit storage_tries_end Passed down.
// @param left The ExtensionNode from the previous state.
// @param right The resolved node from the current state (OptionalInternalNode).
// @param path The path traversed so far.
// @param account_address The current account address (0 for state trie).
// @return Updates diff lists based on the comparison results.
func _left_is_extension_node{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountDiffEntry*,
    storage_tries_end: StorageDiffEntry*,
}(
    left: ExtensionNode, right: OptionalInternalNode, path: Bytes, account_address: OptionalAddress
) -> () {
    alloc_locals;
    check_extension_node(left);

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
        check_leaf_node(path, r_leaf);
        let l_prefix_r = Bytes__startswith__(r_leaf.value.rest_of_key, left.value.key_segment);
        if (l_prefix_r.value != 0) {
            let updated_path = Bytes__add__(path, left.value.key_segment);
            let l_subnode = OptionalUnionInternalNodeExtendedImpl.from_extended(left.value.subnode);
            // Update the right leaf node's rest of key to remove the left node's key segment
            tempvar r_leaf = LeafNode(
                new LeafNodeStruct(
                    rest_of_key=Bytes(
                        new BytesStruct(
                            data=r_leaf.value.rest_of_key.value.data +
                            left.value.key_segment.value.len,
                            len=r_leaf.value.rest_of_key.value.len -
                            left.value.key_segment.value.len,
                        ),
                    ),
                    value=r_leaf.value.value,
                ),
            );

            let r_leaf_typed = OptionalUnionInternalNodeExtendedImpl.from_leaf(r_leaf);
            return _compute_diff(
                left=l_subnode,
                right=r_leaf_typed,
                path=updated_path,
                account_address=account_address,
            );
        }

        // else, the left extension node key segment is not a prefix of the right leaf node rest of key
        // this means that the left extension node is deleted and the right leaf node is created
        // we explore the subnode of the left extension node to find all deleted nodes
        // we log the right leaf node as a new leaf node
        let null_node = OptionalUnionInternalNodeExtended(
            cast(0, OptionalUnionInternalNodeExtendedEnum*)
        );
        // Compute diffs in the right sub-tree
        let updated_path_left = Bytes__add__(path, left.value.key_segment);
        let l_subnode = OptionalUnionInternalNodeExtendedImpl.from_extended(left.value.subnode);
        _compute_diff(
            left=l_subnode, right=null_node, path=updated_path_left, account_address=account_address
        );

        // Compute deletions in the left sub-tree
        let updated_path_right = Bytes__add__(path, r_leaf.value.rest_of_key);
        let updated_path_right_nibbles = nibble_list_to_bytes(updated_path_right);
        let updated_path_right_b32 = Bytes_to_Bytes32(updated_path_right_nibbles);
        let opt_left_leaf = OptionalLeafNode(cast(0, LeafNodeStruct*));
        let opt_right_leaf = OptionalLeafNode(r_leaf.value);

        if (account_address.value == 0) {
            _process_account_diff(
                path=updated_path_right_b32, left=opt_left_leaf, right=opt_right_leaf
            );
            return ();
        }

        _process_storage_diff(
            address=Address([account_address.value]),
            path=updated_path_right_b32,
            left=opt_left_leaf,
            right=opt_right_leaf,
        );

        return ();
    }

    // (ExtensionNode(), ExtensionNode()) ->
    if (cast(right.value.extension_node.value, felt) != 0) {
        let r_extension = right.value.extension_node;
        check_extension_node(r_extension);
        let keys_equal = Bytes__eq__(left.value.key_segment, r_extension.value.key_segment);
        if (keys_equal.value != 0) {
            // equal keys -> look for diffs in children
            let l_subnode = OptionalUnionInternalNodeExtendedImpl.from_extended(left.value.subnode);
            let r_subnode = OptionalUnionInternalNodeExtendedImpl.from_extended(
                r_extension.value.subnode
            );
            let updated_path = Bytes__add__(path, left.value.key_segment);
            return _compute_diff(
                left=l_subnode, right=r_subnode, path=updated_path, account_address=account_address
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

            let l_shortened = OptionalUnionInternalNodeExtendedImpl.from_extension(
                shortened_left_ext
            );
            let r_subnode = OptionalUnionInternalNodeExtendedImpl.from_extended(
                r_extension.value.subnode
            );
            return _compute_diff(
                left=l_shortened,
                right=r_subnode,
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

            let l_subnode = OptionalUnionInternalNodeExtendedImpl.from_extended(left.value.subnode);
            let r_shortened = OptionalUnionInternalNodeExtendedImpl.from_extension(
                shortened_right_ext
            );
            return _compute_diff(
                left=l_subnode,
                right=r_shortened,
                path=updated_path,
                account_address=account_address,
            );
        }

        // Both are different -> look for diffs in both sub-trees
        let null_node = OptionalUnionInternalNodeExtended(
            cast(0, OptionalUnionInternalNodeExtendedEnum*)
        );

        let l_subnode_typed = OptionalUnionInternalNodeExtendedImpl.from_extended(
            left.value.subnode
        );
        let updated_path_left = Bytes__add__(path, left.value.key_segment);
        _compute_diff(
            left=l_subnode_typed,
            right=null_node,
            path=updated_path_left,
            account_address=account_address,
        );

        let r_subnode_typed = OptionalUnionInternalNodeExtendedImpl.from_extended(
            r_extension.value.subnode
        );
        let updated_path_right = Bytes__add__(path, r_extension.value.key_segment);
        _compute_diff(
            left=null_node,
            right=r_subnode_typed,
            path=updated_path_right,
            account_address=account_address,
        );
        return ();
    }

    // (ExtensionNode(), BranchNode())
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

    with_attr error_message("TypeError") {
        jmp raise.raise_label;
    }
}

// @notice Handles the diff computation case where the left node is a BranchNode.
// @dev Compares the left BranchNode with the resolved right node (Null, Leaf, Extension, Branch).
//      Delegates comparison logic to helper functions based on the right node type.
// @implicit node_store Passed down.
// @implicit address_preimages Passed down.
// @implicit storage_key_preimages Passed down.
// @implicit main_trie_end Passed down.
// @implicit storage_tries_end Passed down.
// @param left The BranchNode from the previous state.
// @param right The resolved node from the current state (OptionalInternalNode).
// @param path The path traversed so far.
// @param account_address The current account address (0 for state trie).
// @return Updates diff lists via helper functions.
func _left_is_branch_node{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountDiffEntry*,
    storage_tries_end: StorageDiffEntry*,
}(left: BranchNode, right: OptionalInternalNode, path: Bytes, account_address: OptionalAddress) -> (
    ) {
    alloc_locals;
    check_branch_node(left);

    // (BranchNode(), None) -> deleted branch node
    // Look for diffs in all branches of the left sub-tree
    if (cast(right.value, felt) == 0) {
        return _compute_left_branch_on_none(
            left=left, right=right, path=path, account_address=account_address, index=0
        );
    }

    // (BranchNode(), LeafNode()) -> The branch was deleted and replaced by a single leaf.
    // All branches - except the one whose first nibble matches the leaf's key - are deleted.
    // The remaining branch is compared to the leaf.
    if (cast(right.value.leaf_node.value, felt) != 0) {
        let right_leaf = right.value.leaf_node;
        check_leaf_node(path, right_leaf);
        return _compute_left_branch_on_right_leaf(
            left=left, right=right_leaf, path=path, account_address=account_address, index=0
        );
    }

    // (BranchNode(), ExtensionNode()) -> Match on the corresponding nibble of the extension key
    // segment. Remove the nibble from the extension key segment and look for diffs in the
    // remaining sub-tree.
    if (cast(right.value.extension_node.value, felt) != 0) {
        let right_extension = right.value.extension_node;
        check_extension_node(right_extension);
        return _compute_left_branch_on_right_extension_node(
            left=left, right=right_extension, path=path, account_address=account_address, index=0
        );
    }

    // (BranchNode(), BranchNode()) -> Look for diffs in all branches of the right sub-tree
    if (cast(right.value.branch_node.value, felt) != 0) {
        let right_branch = right.value.branch_node;
        check_branch_node(right_branch);
        return _compute_left_branch_on_right_branch_node(
            left=left, right=right_branch, path=path, account_address=account_address, index=0
        );
    }

    with_attr error_message("TypeError") {
        jmp raise.raise_label;
    }
}

// @notice Helper function for `_left_is_branch_node`: computes diff when right node is Null.
// @dev Recursively calls `_compute_diff` for each subnode of the left BranchNode, comparing it
//      against a null node to register deletions.
// @implicit node_store Passed down.
// @implicit address_preimages Passed down.
// @implicit storage_key_preimages Passed down.
// @implicit main_trie_end Passed down.
// @implicit storage_tries_end Passed down.
// @param left The BranchNode from the previous state.
// @param right The Null node from the current state (OptionalInternalNode).
// @param path The path up to the branch node.
// @param account_address The current account address.
// @param index The current subnode index being processed (0-15).
// @return Updates diff lists via recursive calls.
func _compute_left_branch_on_none{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountDiffEntry*,
    storage_tries_end: StorageDiffEntry*,
}(
    left: BranchNode,
    right: OptionalInternalNode,
    path: Bytes,
    account_address: OptionalAddress,
    index: felt,
) -> () {
    alloc_locals;

    if (index == 16) {
        return ();
    }

    let subnodes_ptr = cast(left.value.subnodes.value, felt*);
    let subnode_i_extended = Extended(cast(subnodes_ptr[index], ExtendedEnum*));
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

    _compute_diff(left=subnode_i, right=null_node, path=sub_path, account_address=account_address);
    return _compute_left_branch_on_none(
        left=left, right=right, path=path, account_address=account_address, index=index + 1
    );
}

// @notice Helper function for `_left_is_branch_node`: computes diff when right node is LeafNode.
// @dev Recursively calls `_compute_diff` for each subnode of the left BranchNode. Compares
//      against the (potentially shortened) right LeafNode if the index matches the leaf's
//      first nibble, otherwise compares against a null node.
// @implicit node_store Passed down.
// @implicit address_preimages Passed down.
// @implicit storage_key_preimages Passed down.
// @implicit main_trie_end Passed down.
// @implicit storage_tries_end Passed down.
// @param left The BranchNode from the previous state.
// @param right The LeafNode from the current state.
// @param path The path up to the branch node.
// @param account_address The current account address.
// @param index The current subnode index being processed (0-15).
// @return Updates diff lists via recursive calls.
func _compute_left_branch_on_right_leaf{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountDiffEntry*,
    storage_tries_end: StorageDiffEntry*,
}(
    left: BranchNode, right: LeafNode, path: Bytes, account_address: OptionalAddress, index: felt
) -> () {
    alloc_locals;

    if (index == 16) {
        return ();
    }

    let subnodes_ptr = cast(left.value.subnodes.value, felt*);
    let subnode_i_extended = Extended(cast(subnodes_ptr[index], ExtendedEnum*));
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
        tempvar right_leaf_shortened = LeafNode(
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
        let right_shortened = OptionalUnionInternalNodeExtendedImpl.from_leaf(right_leaf_shortened);
        _compute_diff(
            left=subnode_i, right=right_shortened, path=sub_path, account_address=account_address
        );
        return _compute_left_branch_on_right_leaf(
            left=left, right=right, path=path, account_address=account_address, index=index + 1
        );
    }
    // Compare to None
    tempvar null_node = OptionalUnionInternalNodeExtended(
        cast(0, OptionalUnionInternalNodeExtendedEnum*)
    );
    _compute_diff(left=subnode_i, right=null_node, path=sub_path, account_address=account_address);

    return _compute_left_branch_on_right_leaf(
        left=left, right=right, path=path, account_address=account_address, index=index + 1
    );
}

// @notice Helper function for `_left_is_branch_node`: computes diff when right node is ExtensionNode.
// @dev Recursively calls `_compute_diff` for each subnode of the left BranchNode. Compares
//      against the (potentially shortened) right ExtensionNode if the index matches the
//      extension's first nibble, otherwise compares against a null node.
// @implicit node_store Passed down.
// @implicit address_preimages Passed down.
// @implicit storage_key_preimages Passed down.
// @implicit main_trie_end Passed down.
// @implicit storage_tries_end Passed down.
// @param left The BranchNode from the previous state.
// @param right The ExtensionNode from the current state.
// @param path The path up to the branch node.
// @param account_address The current account address.
// @param index The current subnode index being processed (0-15).
// @return Updates diff lists via recursive calls.
func _compute_left_branch_on_right_extension_node{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountDiffEntry*,
    storage_tries_end: StorageDiffEntry*,
}(
    left: BranchNode,
    right: ExtensionNode,
    path: Bytes,
    account_address: OptionalAddress,
    index: felt,
) -> () {
    alloc_locals;

    if (index == 16) {
        return ();
    }

    let subnodes_ptr = cast(left.value.subnodes.value, felt*);
    let subnode_i_extended = Extended(cast(subnodes_ptr[index], ExtendedEnum*));
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
        // the length of the key segment is always _at least_ one in an extension
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
        let right_shortened = OptionalUnionInternalNodeExtendedImpl.from_extension(extension);
        _compute_diff(
            left=subnode_i, right=right_shortened, path=sub_path, account_address=account_address
        );
        return _compute_left_branch_on_right_extension_node(
            left=left, right=right, path=path, account_address=account_address, index=index + 1
        );
    }
    // Compare to None
    let null_node = OptionalUnionInternalNodeExtended(
        cast(0, OptionalUnionInternalNodeExtendedEnum*)
    );
    _compute_diff(left=subnode_i, right=null_node, path=sub_path, account_address=account_address);
    return _compute_left_branch_on_right_extension_node(
        left=left, right=right, path=path, account_address=account_address, index=index + 1
    );
}

// @notice Helper function for `_left_is_branch_node`: computes diff when right node is BranchNode.
// @dev Recursively calls `_compute_diff` comparing the corresponding subnodes (at the same index)
//      of the left and right BranchNodes.
// @implicit node_store Passed down.
// @implicit address_preimages Passed down.
// @implicit storage_key_preimages Passed down.
// @implicit main_trie_end Passed down.
// @implicit storage_tries_end Passed down.
// @param left The BranchNode from the previous state.
// @param right The BranchNode from the current state.
// @param path The path up to the branch nodes.
// @param account_address The current account address.
// @param index The current subnode index being processed (0-15).
// @return Updates diff lists via recursive calls.
func _compute_left_branch_on_right_branch_node{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountDiffEntry*,
    storage_tries_end: StorageDiffEntry*,
}(
    left: BranchNode, right: BranchNode, path: Bytes, account_address: OptionalAddress, index: felt
) -> () {
    alloc_locals;

    if (index == 16) {
        return ();
    }

    let subnodes_left_ptr = cast(left.value.subnodes.value, felt*);
    let subnode_left_extended = Extended(cast(subnodes_left_ptr[index], ExtendedEnum*));
    let subnode_left = OptionalUnionInternalNodeExtendedImpl.from_extended(subnode_left_extended);

    let subnodes_right_ptr = cast(right.value.subnodes.value, felt*);
    let subnode_right_extended = Extended(cast(subnodes_right_ptr[index], ExtendedEnum*));
    let subnode_right = OptionalUnionInternalNodeExtendedImpl.from_extended(subnode_right_extended);

    // path = path + bytes([i])
    let path_copy = Bytes__copy__(path);
    assert path_copy.value.data[path_copy.value.len] = index;
    tempvar sub_path = Bytes(
        new BytesStruct(data=path_copy.value.data, len=path_copy.value.len + 1)
    );

    _compute_diff(
        left=subnode_left, right=subnode_right, path=sub_path, account_address=account_address
    );

    return _compute_left_branch_on_right_branch_node(
        left=left, right=right, path=path, account_address=account_address, index=index + 1
    );
}

// @notice Processes differences when the left node is a Leaf/Null and the right node is a Branch.
// @dev Recursively processes each subnode (index 0-15) of the right branch.
//      If the left node is a Leaf, compares the right subnode against the (potentially shortened)
//      left leaf if the index matches the leaf's first nibble, otherwise compares against null.
//      If the left node is Null, compares the right subnode against null.
// @implicit node_store Passed down.
// @implicit address_preimages Passed down.
// @implicit storage_key_preimages Passed down.
// @implicit main_trie_end Passed down.
// @implicit storage_tries_end Passed down.
// @param left The Optional Leaf Node (or Null) from the previous state.
// @param subnodes The subnodes structure of the right BranchNode.
// @param path The path traversed so far.
// @param account_address The current account address.
// @param index The current branch index being processed (0-15).
// @return Updates diff lists via recursive calls to `_compute_diff`.
func _compute_left_leaf_diff_on_right_branch_node{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountDiffEntry*,
    storage_tries_end: StorageDiffEntry*,
}(
    left: OptionalUnionInternalNodeExtended,
    subnodes: Subnodes,
    path: Bytes,
    account_address: OptionalAddress,
    index: felt,
) -> () {
    alloc_locals;

    if (index == 16) {
        return ();
    }

    // Use `branch_0` as the base pointer to the list of subnodes and index it as a felt*.
    let subnodes_ptr = cast(subnodes.value, felt*);
    let subnode_i_extended = Extended(cast(subnodes_ptr[index], ExtendedEnum*));
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
        tempvar left_to_compare_in_iter = left;
    } else {
        // Leaf node
        let l_leaf = left.value.leaf;
        let first_nib = l_leaf.value.rest_of_key.value.data[0];
        if (first_nib == index) {
            // Compare to the shortened leaf node
            tempvar shortened_leaf = LeafNode(
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
            let left_ = OptionalUnionInternalNodeExtendedImpl.from_leaf(shortened_leaf);
            tempvar left_to_compare_in_iter = left_;
        } else {
            // Compare to None
            tempvar left_to_compare_in_iter = OptionalUnionInternalNodeExtended(
                cast(0, OptionalUnionInternalNodeExtendedEnum*)
            );
        }
    }
    let left_to_compare_in_iter = OptionalUnionInternalNodeExtended(
        cast([ap - 1], OptionalUnionInternalNodeExtendedEnum*)
    );

    _compute_diff(
        left=left_to_compare_in_iter,
        right=subnode_i,
        path=sub_path,
        account_address=account_address,
    );

    return _compute_left_leaf_diff_on_right_branch_node(
        left=left, subnodes=subnodes, path=path, account_address=account_address, index=index + 1
    );
}

// @notice Processes differences when the left node is an ExtensionNode and the right node is a Branch.
// @dev Recursively processes each subnode (index 0-15) of the right branch.
//      Compares the right subnode against the (potentially shortened or resolved) left ExtensionNode
//      if the index matches the extension's first nibble, otherwise compares against null.
// @implicit node_store Passed down.
// @implicit address_preimages Passed down.
// @implicit storage_key_preimages Passed down.
// @implicit main_trie_end Passed down.
// @implicit storage_tries_end Passed down.
// @param left The Optional Extension Node from the previous state.
// @param subnodes The subnodes structure of the right BranchNode.
// @param path The path traversed so far.
// @param account_address The current account address.
// @param index The current branch index being processed (0-15).
// @return Updates diff lists via recursive calls to `_compute_diff`.
// TODO: left should not be optional
func _compute_left_extension_node_diff_on_right_branch_node{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    node_store: NodeStore,
    address_preimages: MappingBytes32Address,
    storage_key_preimages: MappingBytes32Bytes32,
    main_trie_end: AddressAccountDiffEntry*,
    storage_tries_end: StorageDiffEntry*,
}(
    left: OptionalUnionInternalNodeExtended,
    subnodes: Subnodes,
    path: Bytes,
    account_address: OptionalAddress,
    index: felt,
) -> () {
    alloc_locals;
    if (index == 16) {
        return ();
    }

    // Use `branch_0` as the base pointer to the list of subnodes and index it as a felt*.
    let subnodes_ptr = cast(subnodes.value, felt*);
    let subnode_i_extended = Extended(cast(subnodes_ptr[index], ExtendedEnum*));
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
    // case we compare to the subnode
    // 2. It doesn't in which case we compare to null.

    let l_extension = left.value.extension;
    let first_nib = l_extension.value.key_segment.value.data[0];
    if (first_nib == index) {
        // Fully consumed by this nibble: compare to the subnode
        if (l_extension.value.key_segment.value.len == 1) {
            let node_to_compare_ = OptionalUnionInternalNodeExtendedImpl.from_extended(
                l_extension.value.subnode
            );
            tempvar node_to_compare = node_to_compare_;
        } else {
            // Compare to the shortened extension node
            tempvar shortened_extension = ExtensionNode(
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
            let node_to_compare_ = OptionalUnionInternalNodeExtendedImpl.from_extension(
                shortened_extension
            );
            tempvar node_to_compare = node_to_compare_;
        }
        let left_ = OptionalUnionInternalNodeExtended(
            cast([ap - 1], OptionalUnionInternalNodeExtendedEnum*)
        );
        tempvar left_to_compare_in_iter = left_;
    } else {
        // Compare to None
        tempvar left_to_compare_in_iter = OptionalUnionInternalNodeExtended(
            cast(0, OptionalUnionInternalNodeExtendedEnum*)
        );
    }
    let left_to_compare_in_iter = OptionalUnionInternalNodeExtended(
        cast([ap - 1], OptionalUnionInternalNodeExtendedEnum*)
    );

    _compute_diff(
        left=left_to_compare_in_iter,
        right=subnode_i,
        path=sub_path,
        account_address=account_address,
    );

    return _compute_left_extension_node_diff_on_right_branch_node(
        left=left, subnodes=subnodes, path=path, account_address=account_address, index=index + 1
    );
}

// @notice Retrieves a node from the node store dictionary by its hash.
// @dev Uses the poseidon hash components (low, high) as the key to look up the node pointer
//      in the `node_store` dictionary. Handles the special case for the empty trie hash.
// @implicit poseidon_ptr Used for hashing if needed by `hashdict_read`.
// @implicit node_store The NodeStore containing the hash-to-node mapping.
// @param node_hash The Hash32 of the node to retrieve.
// @return The retrieved OptionalInternalNode (pointer to the node's enum or 0 if not found/empty hash).
func node_store_get{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    node_store: NodeStore,
}(node_hash: Hash32) -> OptionalInternalNode {
    alloc_locals;

    // The empty trie hash has no corresponding node in the node store.
    // we early return None in this case.
    if (node_hash.value.low == EMPTY_TRIE_HASH_LOW and
        node_hash.value.high == EMPTY_TRIE_HASH_HIGH) {
        let res = OptionalInternalNode(cast(0, InternalNodeEnum*));
        return res;
    }

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

    // Cast the result to a Bytes, hash it to check invariant and RLP-decode it.
    if (pointer == 0) {
        let res = OptionalInternalNode(cast(0, InternalNodeEnum*));
        return res;
    }
    tempvar encoded_node = Bytes(cast(pointer, BytesStruct*));
    let hash = keccak256(encoded_node);
    // Invariant
    with_attr error_message("INVARIANT: NodeStore preimage hash mismatch") {
        assert hash.value.low = node_hash.value.low;
        assert hash.value.high = node_hash.value.high;
    }
    let decoded_node = decode_to_internal_node(encoded_node);
    let result = OptionalInternalNode(decoded_node.value);
    return result;
}

// @notice Resolves an OptionalUnionInternalNodeExtended to an OptionalInternalNode.
// @dev Handles different representations of trie nodes within the Extended type:
//      1. Direct InternalNode (Leaf, Extension, Branch): Returns it directly.
//      2. Bytes: Interprets as a 32-byte hash, fetches the node from `node_store_get`, or returns null for empty bytes.
//      3. Sequence: Interprets as an RLP-encoded embedded node, decodes it using `deserialize_to_internal_node`.
//      Returns null if the input `node` is null or if resolution fails (e.g., invalid Bytes length).
// @implicit node_store Used by `node_store_get`.
// @param node The OptionalUnionInternalNodeExtended node reference to resolve.
// @return The resolved OptionalInternalNode (pointer to InternalNodeEnum or 0).
func resolve{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
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

        let result = node_store_get(node_hash);

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

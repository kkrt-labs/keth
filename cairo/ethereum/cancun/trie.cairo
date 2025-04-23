from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.default_dict import default_dict_new
from starkware.cairo.common.builtin_poseidon.poseidon import poseidon_hash, poseidon_hash_many
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.bitwise import BitwiseBuiltin
from starkware.cairo.common.dict import DictAccess
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.cairo_builtins import KeccakBuiltin
from starkware.cairo.common.memcpy import memcpy

from legacy.utils.bytes import uint256_to_bytes32_little
from legacy.utils.dict import hashdict_read, hashdict_write, dict_new_empty, dict_read, dict_squash
from ethereum.crypto.hash import hash_with
from ethereum.utils.numeric import min
from ethereum_rlp.rlp import encode, _encode_bytes, _encode, Extended__eq__
from ethereum.utils.numeric import U256__eq__
from ethereum_types.numeric import U256, Uint, bool, U256Struct
from ethereum_types.bytes import (
    HashedBytes,
    HashedBytes32,
    Bytes,
    Bytes20,
    BytesStruct,
    Bytes32,
    Bytes32Struct,
    StringStruct,
    String,
    MappingBytesBytes,
    MappingBytesBytesStruct,
    BytesBytesDictAccess,
    TupleMappingBytesBytes,
    TupleMappingBytesBytesStruct,
)
from ethereum.cancun.blocks import (
    Receipt,
    ReceiptStruct,
    Withdrawal,
    WithdrawalStruct,
    UnionBytesLegacyTransaction,
    UnionBytesLegacyTransactionEnum,
    OptionalUnionBytesLegacyTransaction,
    UnionBytesReceipt,
    UnionBytesReceiptEnum,
    OptionalUnionBytesReceipt,
    UnionBytesWithdrawal,
    UnionBytesWithdrawalEnum,
    OptionalUnionBytesWithdrawal,
)
from ethereum.cancun.fork_types import (
    Account,
    Account__eq__,
    AccountStruct,
    Address,
    OptionalAccount,
    TupleAddressBytes32,
    TupleAddressBytes32Struct,
    TupleAddressBytes32U256DictAccess,
    MappingAddressAccount,
    MappingAddressAccountStruct,
    AddressAccountDictAccess,
    MappingTupleAddressBytes32U256,
    MappingTupleAddressBytes32U256Struct,
    OptionalMappingAddressBytes32,
    MappingAddressBytes32,
    MappingAddressBytes32Struct,
    AddressBytes32DictAccess,
    Root,
)
from ethereum.cancun.transactions_types import LegacyTransaction, LegacyTransactionStruct
from ethereum_rlp.rlp import (
    Extended,
    SequenceExtended,
    SequenceExtendedStruct,
    ExtendedEnum,
    ExtendedImpl,
    encode_account,
    encode_legacy_transaction,
    encode_receipt,
    encode_withdrawal,
    encode_uint,
    encode_u256,
)
from ethereum.utils.numeric import divmod
from ethereum.utils.bytes import Bytes32_to_Bytes, Bytes20_to_Bytes, Bytes_to_Bytes32, Bytes__eq__

from legacy.utils.dict import default_dict_finalize

from cairo_core.comparison import is_zero
from cairo_core.control_flow import raise

struct LeafNodeStruct {
    rest_of_key: Bytes,
    value: Extended,
}

struct LeafNode {
    value: LeafNodeStruct*,
}

func LeafNode__eq__(left: LeafNode, right: LeafNode) -> bool {
    let key_eq = Bytes__eq__(left.value.rest_of_key, right.value.rest_of_key);
    if (key_eq.value == 0) {
        return key_eq;
    }

    let value_eq = Extended__eq__(left.value.value, right.value.value);
    if (value_eq.value == 0) {
        return value_eq;
    }

    let res = bool(1);
    return res;
}

struct OptionalLeafNode {
    value: LeafNodeStruct*,
}

struct ExtensionNodeStruct {
    key_segment: Bytes,
    subnode: Extended,
}

struct ExtensionNode {
    value: ExtensionNodeStruct*,
}

func ExtensionNode__eq__(left: ExtensionNode, right: ExtensionNode) -> bool {
    let key_eq = Bytes__eq__(left.value.key_segment, right.value.key_segment);
    if (key_eq.value == 0) {
        let res = bool(0);
        return res;
    }

    let subnode_eq = Extended__eq__(left.value.subnode, right.value.subnode);
    if (subnode_eq.value == 0) {
        let res = bool(0);
        return res;
    }
    let res = bool(1);
    return res;
}

struct SubnodesStruct {
    branch_0: Extended,
    branch_1: Extended,
    branch_2: Extended,
    branch_3: Extended,
    branch_4: Extended,
    branch_5: Extended,
    branch_6: Extended,
    branch_7: Extended,
    branch_8: Extended,
    branch_9: Extended,
    branch_10: Extended,
    branch_11: Extended,
    branch_12: Extended,
    branch_13: Extended,
    branch_14: Extended,
    branch_15: Extended,
}

struct Subnodes {
    value: SubnodesStruct*,
}

func Subnodes__eq__(left: Subnodes, right: Subnodes) -> bool {
    let branch0_eq = Extended__eq__(left.value.branch_0, right.value.branch_0);
    if (branch0_eq.value == 0) {
        let res = bool(0);
        return res;
    }
    let branch1_eq = Extended__eq__(left.value.branch_1, right.value.branch_1);
    if (branch1_eq.value == 0) {
        let res = bool(0);
        return res;
    }
    let branch2_eq = Extended__eq__(left.value.branch_2, right.value.branch_2);
    if (branch2_eq.value == 0) {
        let res = bool(0);
        return res;
    }
    let branch3_eq = Extended__eq__(left.value.branch_3, right.value.branch_3);
    if (branch3_eq.value == 0) {
        let res = bool(0);
        return res;
    }
    let branch4_eq = Extended__eq__(left.value.branch_4, right.value.branch_4);
    if (branch4_eq.value == 0) {
        let res = bool(0);
        return res;
    }
    let branch5_eq = Extended__eq__(left.value.branch_5, right.value.branch_5);
    if (branch5_eq.value == 0) {
        let res = bool(0);
        return res;
    }
    let branch6_eq = Extended__eq__(left.value.branch_6, right.value.branch_6);
    if (branch6_eq.value == 0) {
        let res = bool(0);
        return res;
    }
    let branch7_eq = Extended__eq__(left.value.branch_7, right.value.branch_7);
    if (branch7_eq.value == 0) {
        let res = bool(0);
        return res;
    }
    let branch8_eq = Extended__eq__(left.value.branch_8, right.value.branch_8);
    if (branch8_eq.value == 0) {
        let res = bool(0);
        return res;
    }
    let branch9_eq = Extended__eq__(left.value.branch_9, right.value.branch_9);
    if (branch9_eq.value == 0) {
        let res = bool(0);
        return res;
    }
    let branch10_eq = Extended__eq__(left.value.branch_10, right.value.branch_10);
    if (branch10_eq.value == 0) {
        let res = bool(0);
        return res;
    }
    let branch11_eq = Extended__eq__(left.value.branch_11, right.value.branch_11);
    if (branch11_eq.value == 0) {
        let res = bool(0);
        return res;
    }
    let branch12_eq = Extended__eq__(left.value.branch_12, right.value.branch_12);
    if (branch12_eq.value == 0) {
        let res = bool(0);
        return res;
    }
    let branch13_eq = Extended__eq__(left.value.branch_13, right.value.branch_13);
    if (branch13_eq.value == 0) {
        let res = bool(0);
        return res;
    }
    let branch14_eq = Extended__eq__(left.value.branch_14, right.value.branch_14);
    if (branch14_eq.value == 0) {
        let res = bool(0);
        return res;
    }
    let branch15_eq = Extended__eq__(left.value.branch_15, right.value.branch_15);
    if (branch15_eq.value == 0) {
        let res = bool(0);
        return res;
    }
    let res = bool(1);
    return res;
}

struct BranchNodeStruct {
    subnodes: Subnodes,
    value: Extended,
}

struct BranchNode {
    value: BranchNodeStruct*,
}

func BranchNode__eq__(left: BranchNode, right: BranchNode) -> bool {
    let subnodes_eq = Subnodes__eq__(left.value.subnodes, right.value.subnodes);
    if (subnodes_eq.value == 0) {
        let res = bool(0);
        return res;
    }
    let value_eq = Extended__eq__(left.value.value, right.value.value);
    return value_eq;
}

struct InternalNode {
    value: InternalNodeEnum*,
}

struct OptionalInternalNode {
    value: InternalNodeEnum*,
}

struct InternalNodeEnum {
    leaf_node: LeafNode,
    extension_node: ExtensionNode,
    branch_node: BranchNode,
}

namespace InternalNodeImpl {
    func leaf_node(leaf_node: LeafNode) -> InternalNode {
        tempvar result = InternalNode(
            new InternalNodeEnum(
                leaf_node=leaf_node,
                extension_node=ExtensionNode(cast(0, ExtensionNodeStruct*)),
                branch_node=BranchNode(cast(0, BranchNodeStruct*)),
            ),
        );
        return result;
    }

    func extension_node(extension_node: ExtensionNode) -> InternalNode {
        tempvar result = InternalNode(
            new InternalNodeEnum(
                leaf_node=LeafNode(cast(0, LeafNodeStruct*)),
                extension_node=extension_node,
                branch_node=BranchNode(cast(0, BranchNodeStruct*)),
            ),
        );
        return result;
    }

    func branch_node(branch_node: BranchNode) -> InternalNode {
        tempvar result = InternalNode(
            new InternalNodeEnum(
                leaf_node=LeafNode(cast(0, LeafNodeStruct*)),
                extension_node=ExtensionNode(cast(0, ExtensionNodeStruct*)),
                branch_node=branch_node,
            ),
        );
        return result;
    }
}

struct TrieAddressOptionalAccountStruct {
    secured: bool,
    default: OptionalAccount,
    _data: MappingAddressAccount,
}

struct TrieAddressOptionalAccount {
    value: TrieAddressOptionalAccountStruct*,
}

// Internal representation of the Dict[Address, Trie[Bytes32, U256]]
// which holds the storage tries for each account.
// During execution, the storage tries are "merged" into a single trie where the keys are
// the hash of the account address and the storage key.
struct TrieTupleAddressBytes32U256Struct {
    secured: bool,
    default: U256,
    _data: MappingTupleAddressBytes32U256,
}

struct TrieTupleAddressBytes32U256 {
    value: TrieTupleAddressBytes32U256Struct*,
}

// To compute storage roots, we will extract mapping of all storage tries for each account.
struct Bytes32U256DictAccess {
    key: HashedBytes32,
    prev_value: U256,
    new_value: U256,
}

struct MappingBytes32U256Struct {
    dict_ptr_start: Bytes32U256DictAccess*,
    dict_ptr: Bytes32U256DictAccess*,
    parent_dict: MappingBytes32U256Struct*,
}

struct MappingBytes32U256 {
    value: MappingBytes32U256Struct*,
}

struct TrieBytes32U256Struct {
    secured: bool,
    default: U256,
    _data: MappingBytes32U256,
}

struct TrieBytes32U256 {
    value: TrieBytes32U256Struct*,
}

struct BytesOptionalUnionBytesLegacyTransactionDictAccess {
    key: HashedBytes,
    prev_value: OptionalUnionBytesLegacyTransaction,
    new_value: OptionalUnionBytesLegacyTransaction,
}

struct MappingBytesOptionalUnionBytesLegacyTransactionStruct {
    dict_ptr_start: BytesOptionalUnionBytesLegacyTransactionDictAccess*,
    dict_ptr: BytesOptionalUnionBytesLegacyTransactionDictAccess*,
    parent_dict: MappingBytesOptionalUnionBytesLegacyTransactionStruct*,
}

struct MappingBytesOptionalUnionBytesLegacyTransaction {
    value: MappingBytesOptionalUnionBytesLegacyTransactionStruct*,
}

struct TrieBytesOptionalUnionBytesLegacyTransactionStruct {
    secured: bool,
    default: OptionalUnionBytesLegacyTransaction,
    _data: MappingBytesOptionalUnionBytesLegacyTransaction,
}

struct TrieBytesOptionalUnionBytesLegacyTransaction {
    value: TrieBytesOptionalUnionBytesLegacyTransactionStruct*,
}

struct BytesOptionalUnionBytesReceiptDictAccess {
    key: HashedBytes,
    prev_value: OptionalUnionBytesReceipt,
    new_value: OptionalUnionBytesReceipt,
}

struct MappingBytesOptionalUnionBytesReceiptStruct {
    dict_ptr_start: BytesOptionalUnionBytesReceiptDictAccess*,
    dict_ptr: BytesOptionalUnionBytesReceiptDictAccess*,
    parent_dict: MappingBytesOptionalUnionBytesReceiptStruct*,
}

struct MappingBytesOptionalUnionBytesReceipt {
    value: MappingBytesOptionalUnionBytesReceiptStruct*,
}

struct TrieBytesOptionalUnionBytesReceiptStruct {
    secured: bool,
    default: OptionalUnionBytesReceipt,
    _data: MappingBytesOptionalUnionBytesReceipt,
}

struct TrieBytesOptionalUnionBytesReceipt {
    value: TrieBytesOptionalUnionBytesReceiptStruct*,
}

struct BytesOptionalUnionBytesWithdrawalDictAccess {
    key: HashedBytes,
    prev_value: OptionalUnionBytesWithdrawal,
    new_value: OptionalUnionBytesWithdrawal,
}

struct MappingBytesOptionalUnionBytesWithdrawalStruct {
    dict_ptr_start: BytesOptionalUnionBytesWithdrawalDictAccess*,
    dict_ptr: BytesOptionalUnionBytesWithdrawalDictAccess*,
    parent_dict: MappingBytesOptionalUnionBytesWithdrawalStruct*,
}

struct MappingBytesOptionalUnionBytesWithdrawal {
    value: MappingBytesOptionalUnionBytesWithdrawalStruct*,
}

struct TrieBytesOptionalUnionBytesWithdrawalStruct {
    secured: bool,
    default: OptionalUnionBytesWithdrawal,
    _data: MappingBytesOptionalUnionBytesWithdrawal,
}

struct TrieBytesOptionalUnionBytesWithdrawal {
    value: TrieBytesOptionalUnionBytesWithdrawalStruct*,
}

struct EthereumTries {
    value: EthereumTriesEnum*,
}

struct EthereumTriesEnum {
    account: TrieAddressOptionalAccount,
    storage: TrieBytes32U256,
    transaction: TrieBytesOptionalUnionBytesLegacyTransaction,
    receipt: TrieBytesOptionalUnionBytesReceipt,
    withdrawal: TrieBytesOptionalUnionBytesWithdrawal,
}

struct NodeEnum {
    account: Account,
    bytes: Bytes,
    legacy_transaction: LegacyTransaction,
    receipt: Receipt,
    uint: Uint*,
    u256: U256,
    withdrawal: Withdrawal,
}

struct Node {
    value: NodeEnum*,
}

func encode_internal_node{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*
}(node: InternalNode, hash_function_name: felt) -> Extended {
    alloc_locals;
    local unencoded: Extended;
    local range_check_ptr_end;

    if (cast(node.value, felt) == 0) {
        jmp none;
    }

    tempvar is_leaf = cast(node.value.leaf_node.value, felt);
    jmp leaf_node if is_leaf != 0;
    tempvar is_extension_node = cast(node.value.extension_node.value, felt);
    jmp extension_node if is_extension_node != 0;
    tempvar is_branch_node = cast(node.value.branch_node.value, felt);
    jmp branch_node if is_branch_node != 0;

    none:
    let (data) = alloc();
    tempvar empty_byte = Bytes(new BytesStruct(data, 0));
    let unencoded = ExtendedImpl.bytes(empty_byte);
    // rlp(b'') = 0x80 so no need to hash
    return unencoded;

    leaf_node:
    let compact = nibble_list_to_compact(node.value.leaf_node.value.rest_of_key, bool(1));
    let compact_extended = ExtendedImpl.bytes(compact);
    let (sequence_data: Extended*) = alloc();
    assert [sequence_data] = compact_extended;
    assert [sequence_data + 1] = node.value.leaf_node.value.value;
    tempvar sequence = SequenceExtended(new SequenceExtendedStruct(sequence_data, 2));
    let unencoded_ = ExtendedImpl.sequence(sequence);
    assert unencoded = unencoded_;
    assert range_check_ptr_end = range_check_ptr;
    jmp common;

    extension_node:
    let compact = nibble_list_to_compact(node.value.extension_node.value.key_segment, bool(0));
    let compact_extended = ExtendedImpl.bytes(compact);
    let (sequence_data: Extended*) = alloc();
    assert [sequence_data] = compact_extended;
    assert [sequence_data + 1] = node.value.extension_node.value.subnode;
    tempvar sequence = SequenceExtended(new SequenceExtendedStruct(sequence_data, 2));
    let unencoded_ = ExtendedImpl.sequence(sequence);
    assert unencoded = unencoded_;
    assert range_check_ptr_end = range_check_ptr;
    jmp common;

    branch_node:
    let (value: Extended*) = alloc();
    let len = 16;
    // TOD0: check if we really need to copy of if we can just use the pointer
    memcpy(value, node.value.branch_node.value.subnodes.value, len);
    assert [value + len] = node.value.branch_node.value.value;
    tempvar sequence = SequenceExtended(new SequenceExtendedStruct(value, len + 1));
    let unencoded_ = ExtendedImpl.sequence(sequence);
    assert unencoded = unencoded_;
    assert range_check_ptr_end = range_check_ptr;
    jmp common;

    common:
    let range_check_ptr = range_check_ptr_end;
    let encoded = encode(unencoded);

    let cond = is_le(encoded.value.len, 32 - 1);
    if (cond == 1) {
        return unencoded;
    }

    let hash = hash_with(encoded, hash_function_name);
    let (data) = alloc();
    uint256_to_bytes32_little(data, [hash.value]);
    let hashed = ExtendedImpl.bytes(Bytes(new BytesStruct(data, 32)));
    return hashed;
}

func encode_node{range_check_ptr}(node: Node, storage_root: Bytes) -> Bytes {
    alloc_locals;

    tempvar is_none = is_zero(cast(node.value, felt));
    jmp none if is_none != 0;

    tempvar is_account = cast(node.value.account.value, felt);
    jmp account if is_account != 0;

    tempvar is_bytes = cast(node.value.bytes.value, felt);
    jmp bytes if is_bytes != 0;

    tempvar is_legacy_transaction = cast(node.value.legacy_transaction.value, felt);
    jmp legacy_transaction if is_legacy_transaction != 0;

    tempvar is_receipt = cast(node.value.receipt.value, felt);
    jmp receipt if is_receipt != 0;

    tempvar is_uint = cast(node.value.uint, felt);
    jmp uint if is_uint != 0;

    tempvar is_u256 = cast(node.value.u256.value, felt);
    jmp u256 if is_u256 != 0;

    tempvar is_withdrawal = cast(node.value.withdrawal.value, felt);
    jmp withdrawal if is_withdrawal != 0;

    none:
    // None defined for type Node but actually not supported in the EELS
    raise('AssertionError');

    account:
    if (cast(storage_root.value, felt) == 0) {
        raise('AssertionError');
    }
    let encoded = encode_account(node.value.account, storage_root);
    return encoded;

    bytes:
    return node.value.bytes;

    legacy_transaction:
    let encoded = encode_legacy_transaction(node.value.legacy_transaction);
    return encoded;

    receipt:
    let encoded = encode_receipt(node.value.receipt);
    return encoded;

    uint:
    // Node is Union[Account, Bytes, LegacyTransaction, Receipt, Uint, U256, Withdrawal, None]
    // but encode_node(Uint) will raise AssertionError in EELS
    raise('AssertionError');

    // TODO: use this code once Uint is supported in the EELS
    // let encoded = encode_uint([node.value.uint]);
    // return encoded;

    u256:
    let encoded = encode_u256(node.value.u256);
    return encoded;

    withdrawal:
    let encoded = encode_withdrawal(node.value.withdrawal);
    return encoded;
}

// @notice Copies the trie to a new segment.
// @dev This function simply creates a new segment for the new dict and associates it with the
// dict_tracker of the source dict.
func copy_TrieAddressOptionalAccount{range_check_ptr, trie: TrieAddressOptionalAccount}(
    ) -> TrieAddressOptionalAccount {
    alloc_locals;
    // TODO: soundness
    // We need to ensure it is sound when finalizing that copy.
    // The full design is:
    // - We create a new segment for the new dict
    // - We copy the python dict tracker and associate it with that new segment
    // - When interacting with the copied trie, we use the new segment with the new dict_ptr
    // - If the state reverts, then upon squashing that copy, we:
    //  - copy all the prev_keys in the new segment to the main segment (as if they were read from the new segment)
    //  - delete the new segment
    //  - This ensures that when squashing the main segment, we ensure that the data read in the new segment matched the data from the main segment.

    local new_dict_ptr: AddressAccountDictAccess*;
    tempvar parent_dict_end = trie.value._data.value.dict_ptr;
    %{ copy_tracker_to_new_ptr %}

    tempvar res = TrieAddressOptionalAccount(
        new TrieAddressOptionalAccountStruct(
            trie.value.secured,
            trie.value.default,
            MappingAddressAccount(
                new MappingAddressAccountStruct(new_dict_ptr, new_dict_ptr, trie.value._data.value)
            ),
        ),
    );
    return res;
}

func copy_TrieTupleAddressBytes32U256{range_check_ptr, trie: TrieTupleAddressBytes32U256}(
    ) -> TrieTupleAddressBytes32U256 {
    alloc_locals;
    // TODO: same as above

    local new_dict_ptr: TupleAddressBytes32U256DictAccess*;
    tempvar parent_dict_end = trie.value._data.value.dict_ptr;
    %{ copy_tracker_to_new_ptr %}

    tempvar res = TrieTupleAddressBytes32U256(
        new TrieTupleAddressBytes32U256Struct(
            trie.value.secured,
            trie.value.default,
            MappingTupleAddressBytes32U256(
                new MappingTupleAddressBytes32U256Struct(
                    new_dict_ptr, new_dict_ptr, trie.value._data.value
                ),
            ),
        ),
    );
    return res;
}

func trie_get_TrieAddressOptionalAccount{
    poseidon_ptr: PoseidonBuiltin*, trie: TrieAddressOptionalAccount
}(key: Address) -> OptionalAccount {
    alloc_locals;
    let dict_ptr = cast(trie.value._data.value.dict_ptr, DictAccess*);

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let (pointer) = hashdict_read{dict_ptr=dict_ptr}(1, &key.value);
    if (pointer == 0) {
        tempvar pointer = cast(trie.value.default.value, felt);
    } else {
        tempvar pointer = pointer;
    }
    let new_dict_ptr = cast(dict_ptr, AddressAccountDictAccess*);
    let parent_dict = trie.value._data.value.parent_dict;
    tempvar mapping = MappingAddressAccount(
        new MappingAddressAccountStruct(
            trie.value._data.value.dict_ptr_start, new_dict_ptr, parent_dict
        ),
    );
    tempvar trie = TrieAddressOptionalAccount(
        new TrieAddressOptionalAccountStruct(trie.value.secured, trie.value.default, mapping)
    );
    tempvar res = OptionalAccount(cast(pointer, AccountStruct*));
    return res;
}

func trie_get_TrieTupleAddressBytes32U256{
    poseidon_ptr: PoseidonBuiltin*, trie: TrieTupleAddressBytes32U256
}(address: Address, key: Bytes32) -> U256 {
    alloc_locals;
    let dict_ptr = cast(trie.value._data.value.dict_ptr, DictAccess*);

    let (keys) = alloc();
    assert keys[0] = address.value;
    assert keys[1] = key.value.low;
    assert keys[2] = key.value.high;

    let (pointer) = hashdict_read{dict_ptr=dict_ptr}(3, keys);
    if (pointer == 0) {
        tempvar pointer = cast(trie.value.default.value, felt);
    } else {
        tempvar pointer = pointer;
    }
    let new_dict_ptr = cast(dict_ptr, TupleAddressBytes32U256DictAccess*);
    let parent_dict = trie.value._data.value.parent_dict;
    tempvar mapping = MappingTupleAddressBytes32U256(
        new MappingTupleAddressBytes32U256Struct(
            trie.value._data.value.dict_ptr_start, new_dict_ptr, parent_dict
        ),
    );
    tempvar trie = TrieTupleAddressBytes32U256(
        new TrieTupleAddressBytes32U256Struct(trie.value.secured, trie.value.default, mapping)
    );
    tempvar res = U256(cast(pointer, U256Struct*));
    return res;
}

func trie_get_TrieBytes32U256{poseidon_ptr: PoseidonBuiltin*, trie: TrieBytes32U256}(
    key: Bytes32
) -> U256 {
    alloc_locals;
    let dict_ptr = cast(trie.value._data.value.dict_ptr, DictAccess*);

    let (keys) = alloc();
    assert keys[0] = key.value.low;
    assert keys[1] = key.value.high;

    let (pointer) = hashdict_read{dict_ptr=dict_ptr}(2, keys);
    if (pointer == 0) {
        tempvar pointer = cast(trie.value.default.value, felt);
    } else {
        tempvar pointer = pointer;
    }
    let new_dict_ptr = cast(dict_ptr, Bytes32U256DictAccess*);
    let parent_dict = trie.value._data.value.parent_dict;
    tempvar mapping = MappingBytes32U256(
        new MappingBytes32U256Struct(
            trie.value._data.value.dict_ptr_start, new_dict_ptr, parent_dict
        ),
    );
    tempvar trie = TrieBytes32U256(
        new TrieBytes32U256Struct(trie.value.secured, trie.value.default, mapping)
    );
    tempvar res = U256(cast(pointer, U256Struct*));
    return res;
}

func trie_get_TrieBytesOptionalUnionBytesLegacyTransaction{
    poseidon_ptr: PoseidonBuiltin*, trie: TrieBytesOptionalUnionBytesLegacyTransaction
}(key: Bytes) -> OptionalUnionBytesLegacyTransaction {
    alloc_locals;
    let dict_ptr = cast(trie.value._data.value.dict_ptr, DictAccess*);

    let (pointer) = hashdict_read{dict_ptr=dict_ptr}(key.value.len, key.value.data);
    if (pointer == 0) {
        tempvar pointer = cast(trie.value.default.value, felt);
    } else {
        tempvar pointer = pointer;
    }
    let new_dict_ptr = cast(dict_ptr, BytesOptionalUnionBytesLegacyTransactionDictAccess*);
    let parent_dict = trie.value._data.value.parent_dict;
    tempvar mapping = MappingBytesOptionalUnionBytesLegacyTransaction(
        new MappingBytesOptionalUnionBytesLegacyTransactionStruct(
            trie.value._data.value.dict_ptr_start, new_dict_ptr, parent_dict
        ),
    );
    tempvar trie = TrieBytesOptionalUnionBytesLegacyTransaction(
        new TrieBytesOptionalUnionBytesLegacyTransactionStruct(
            trie.value.secured, trie.value.default, mapping
        ),
    );
    tempvar res = OptionalUnionBytesLegacyTransaction(
        cast(pointer, UnionBytesLegacyTransactionEnum*)
    );
    return res;
}

func trie_get_TrieBytesOptionalUnionBytesReceipt{
    poseidon_ptr: PoseidonBuiltin*, trie: TrieBytesOptionalUnionBytesReceipt
}(key: Bytes) -> OptionalUnionBytesReceipt {
    alloc_locals;
    let dict_ptr = cast(trie.value._data.value.dict_ptr, DictAccess*);

    let (pointer) = hashdict_read{dict_ptr=dict_ptr}(key.value.len, key.value.data);
    if (pointer == 0) {
        tempvar pointer = cast(trie.value.default.value, felt);
    } else {
        tempvar pointer = pointer;
    }
    let new_dict_ptr = cast(dict_ptr, BytesOptionalUnionBytesReceiptDictAccess*);
    let parent_dict = trie.value._data.value.parent_dict;
    tempvar mapping = MappingBytesOptionalUnionBytesReceipt(
        new MappingBytesOptionalUnionBytesReceiptStruct(
            trie.value._data.value.dict_ptr_start, new_dict_ptr, parent_dict
        ),
    );
    tempvar trie = TrieBytesOptionalUnionBytesReceipt(
        new TrieBytesOptionalUnionBytesReceiptStruct(
            trie.value.secured, trie.value.default, mapping
        ),
    );
    tempvar res = OptionalUnionBytesReceipt(cast(pointer, UnionBytesReceiptEnum*));
    return res;
}

func trie_get_TrieBytesOptionalUnionBytesWithdrawal{
    poseidon_ptr: PoseidonBuiltin*, trie: TrieBytesOptionalUnionBytesWithdrawal
}(key: Bytes) -> OptionalUnionBytesWithdrawal {
    alloc_locals;
    let dict_ptr = cast(trie.value._data.value.dict_ptr, DictAccess*);

    let (pointer) = hashdict_read{dict_ptr=dict_ptr}(key.value.len, key.value.data);
    if (pointer == 0) {
        tempvar pointer = cast(trie.value.default.value, felt);
    } else {
        tempvar pointer = pointer;
    }
    let new_dict_ptr = cast(dict_ptr, BytesOptionalUnionBytesWithdrawalDictAccess*);
    let parent_dict = trie.value._data.value.parent_dict;
    tempvar mapping = MappingBytesOptionalUnionBytesWithdrawal(
        new MappingBytesOptionalUnionBytesWithdrawalStruct(
            trie.value._data.value.dict_ptr_start, new_dict_ptr, parent_dict
        ),
    );
    tempvar trie = TrieBytesOptionalUnionBytesWithdrawal(
        new TrieBytesOptionalUnionBytesWithdrawalStruct(
            trie.value.secured, trie.value.default, mapping
        ),
    );
    tempvar res = OptionalUnionBytesWithdrawal(cast(pointer, UnionBytesWithdrawalEnum*));
    return res;
}

func trie_set_TrieAddressOptionalAccount{
    poseidon_ptr: PoseidonBuiltin*, trie: TrieAddressOptionalAccount
}(key: Address, value: OptionalAccount) {
    let dict_ptr = cast(trie.value._data.value.dict_ptr, DictAccess*);

    let (keys) = alloc();
    assert [keys] = key.value;

    // Writes 0 if value.value is the null ptr
    hashdict_write{dict_ptr=dict_ptr}(1, keys, cast(value.value, felt));

    let new_dict_ptr = cast(dict_ptr, AddressAccountDictAccess*);
    tempvar mapping = MappingAddressAccount(
        new MappingAddressAccountStruct(
            trie.value._data.value.dict_ptr_start, new_dict_ptr, trie.value._data.value.parent_dict
        ),
    );
    tempvar trie = TrieAddressOptionalAccount(
        new TrieAddressOptionalAccountStruct(trie.value.secured, trie.value.default, mapping)
    );
    return ();
}

func trie_set_TrieTupleAddressBytes32U256{
    poseidon_ptr: PoseidonBuiltin*, trie: TrieTupleAddressBytes32U256
}(address: Address, key: Bytes32, value: U256) {
    let dict_ptr = cast(trie.value._data.value.dict_ptr, DictAccess*);

    let is_default = U256__eq__(value, trie.value.default);

    let (keys) = alloc();
    assert keys[0] = address.value;
    assert keys[1] = key.value.low;
    assert keys[2] = key.value.high;

    if (is_default.value != 0) {
        hashdict_write{dict_ptr=dict_ptr}(3, keys, 0);
    } else {
        hashdict_write{dict_ptr=dict_ptr}(3, keys, cast(value.value, felt));
    }
    let new_dict_ptr = cast(dict_ptr, TupleAddressBytes32U256DictAccess*);
    tempvar mapping = MappingTupleAddressBytes32U256(
        new MappingTupleAddressBytes32U256Struct(
            trie.value._data.value.dict_ptr_start, new_dict_ptr, trie.value._data.value.parent_dict
        ),
    );
    tempvar trie = TrieTupleAddressBytes32U256(
        new TrieTupleAddressBytes32U256Struct(trie.value.secured, trie.value.default, mapping)
    );
    return ();
}

func trie_set_TrieBytes32U256{poseidon_ptr: PoseidonBuiltin*, trie: TrieBytes32U256}(
    key: Bytes32, value: U256
) {
    alloc_locals;
    let dict_ptr = cast(trie.value._data.value.dict_ptr, DictAccess*);

    let is_default = U256__eq__(value, trie.value.default);

    let (keys) = alloc();
    assert keys[0] = key.value.low;
    assert keys[1] = key.value.high;

    if (is_default.value != 0) {
        hashdict_write{dict_ptr=dict_ptr}(2, keys, 0);
    } else {
        hashdict_write{dict_ptr=dict_ptr}(2, keys, cast(value.value, felt));
    }

    let new_dict_ptr = cast(dict_ptr, Bytes32U256DictAccess*);
    tempvar mapping = MappingBytes32U256(
        new MappingBytes32U256Struct(
            trie.value._data.value.dict_ptr_start, new_dict_ptr, trie.value._data.value.parent_dict
        ),
    );
    tempvar trie = TrieBytes32U256(
        new TrieBytes32U256Struct(trie.value.secured, trie.value.default, mapping)
    );
    return ();
}
func trie_set_TrieBytesOptionalUnionBytesLegacyTransaction{
    poseidon_ptr: PoseidonBuiltin*, trie: TrieBytesOptionalUnionBytesLegacyTransaction
}(key: Bytes, value: OptionalUnionBytesLegacyTransaction) {
    alloc_locals;
    let dict_ptr = cast(trie.value._data.value.dict_ptr, DictAccess*);

    // Writes 0 if value.value is the null ptr
    hashdict_write{dict_ptr=dict_ptr}(key.value.len, key.value.data, cast(value.value, felt));

    let new_dict_ptr = cast(dict_ptr, BytesOptionalUnionBytesLegacyTransactionDictAccess*);
    tempvar mapping = MappingBytesOptionalUnionBytesLegacyTransaction(
        new MappingBytesOptionalUnionBytesLegacyTransactionStruct(
            trie.value._data.value.dict_ptr_start, new_dict_ptr, trie.value._data.value.parent_dict
        ),
    );
    tempvar trie = TrieBytesOptionalUnionBytesLegacyTransaction(
        new TrieBytesOptionalUnionBytesLegacyTransactionStruct(
            trie.value.secured, trie.value.default, mapping
        ),
    );
    return ();
}

func trie_set_TrieBytesOptionalUnionBytesReceipt{
    poseidon_ptr: PoseidonBuiltin*, trie: TrieBytesOptionalUnionBytesReceipt
}(key: Bytes, value: OptionalUnionBytesReceipt) {
    alloc_locals;
    let dict_ptr = cast(trie.value._data.value.dict_ptr, DictAccess*);

    // Writes 0 if value.value is the null ptr
    hashdict_write{dict_ptr=dict_ptr}(key.value.len, key.value.data, cast(value.value, felt));

    let new_dict_ptr = cast(dict_ptr, BytesOptionalUnionBytesReceiptDictAccess*);
    tempvar mapping = MappingBytesOptionalUnionBytesReceipt(
        new MappingBytesOptionalUnionBytesReceiptStruct(
            trie.value._data.value.dict_ptr_start, new_dict_ptr, trie.value._data.value.parent_dict
        ),
    );

    tempvar trie = TrieBytesOptionalUnionBytesReceipt(
        new TrieBytesOptionalUnionBytesReceiptStruct(
            trie.value.secured, trie.value.default, mapping
        ),
    );
    return ();
}

func trie_set_TrieBytesOptionalUnionBytesWithdrawal{
    poseidon_ptr: PoseidonBuiltin*, trie: TrieBytesOptionalUnionBytesWithdrawal
}(key: Bytes, value: OptionalUnionBytesWithdrawal) {
    alloc_locals;
    let dict_ptr = cast(trie.value._data.value.dict_ptr, DictAccess*);

    // Writes 0 if value.value is the null ptr
    hashdict_write{dict_ptr=dict_ptr}(key.value.len, key.value.data, cast(value.value, felt));

    let new_dict_ptr = cast(dict_ptr, BytesOptionalUnionBytesWithdrawalDictAccess*);
    tempvar mapping = MappingBytesOptionalUnionBytesWithdrawal(
        new MappingBytesOptionalUnionBytesWithdrawalStruct(
            trie.value._data.value.dict_ptr_start, new_dict_ptr, trie.value._data.value.parent_dict
        ),
    );

    tempvar trie = TrieBytesOptionalUnionBytesWithdrawal(
        new TrieBytesOptionalUnionBytesWithdrawalStruct(
            trie.value.secured, trie.value.default, mapping
        ),
    );
    return ();
}

func common_prefix_length(a: Bytes, b: Bytes) -> felt {
    alloc_locals;
    local result;

    %{ common_prefix_length_hint %}

    jmp common if result != 0;
    jmp diff;

    common:
    let index = [ap - 1];
    with_attr error_message("common_prefix_length") {
        assert a.value.data[index - 1] = b.value.data[index - 1];
    }
    tempvar index = index - 1;
    jmp common if index != 0;

    diff:
    let result = [fp];
    if (a.value.len == result) {
        return result;
    }

    if (b.value.len == result) {
        return result;
    }

    with_attr error_message("common_prefix_length") {
        assert_not_zero(a.value.data[result] - b.value.data[result]);
    }

    return result;
}

func nibble_list_to_compact{range_check_ptr: felt}(x: Bytes, is_leaf: bool) -> Bytes {
    alloc_locals;
    let (local compact) = alloc();
    local range_check_ptr_end;
    let len = x.value.len;

    if (len == 0) {
        assert [compact] = 16 * (2 * is_leaf.value);
        tempvar result = Bytes(new BytesStruct(compact, 1));
        return result;
    }

    local remainder;
    %{ value_len_mod_two %}
    with_attr error_message("nibble_list_to_compact: invalid remainder") {
        assert remainder * (1 - remainder) = 0;
        tempvar underflow_check = (x.value.len - remainder) / 2;
        assert [range_check_ptr] = underflow_check;
    }
    let range_check_ptr = range_check_ptr + 1;
    assert [compact] = 16 * (2 * is_leaf.value + remainder) + x.value.data[0] * remainder;

    if (x.value.len == 1) {
        tempvar result = Bytes(new BytesStruct(compact, 1));
        return result;
    }

    tempvar compact = compact + 1;
    tempvar i = remainder;
    assert range_check_ptr_end = range_check_ptr;

    loop:
    let compact = cast([ap - 2], felt*);
    let i = [ap - 1];
    let x_ptr = cast([fp - 4], BytesStruct*);

    assert [compact] = 16 * x_ptr.data[i] + x_ptr.data[i + 1];

    tempvar cond = x_ptr.len - i - 2;
    tempvar compact = compact + 1;
    tempvar i = i + 2;

    jmp loop if cond != 0;

    let len = (i - remainder) / 2;

    let compact = cast([fp], felt*);
    let range_check_ptr = range_check_ptr_end;
    tempvar result = Bytes(new BytesStruct(compact, 1 + len));
    return result;
}

func nibble_list_to_bytes{range_check_ptr: felt, bitwise_ptr: BitwiseBuiltin*}(x: Bytes) -> Bytes {
    alloc_locals;
    let len = x.value.len;

    // Return empty bytes for empty input
    if (len == 0) {
        let (data) = alloc();
        tempvar result = Bytes(new BytesStruct(data, 0));
        return result;
    }

    if (len == 1) {
        let (data) = alloc();
        assert [data] = 16 * x.value.data[0];
        tempvar result = Bytes(new BytesStruct(data, 1));
        return result;
    }

    local remainder;
    %{ value_len_mod_two %}
    with_attr error_message("nibble_list_to_bytes: invalid remainder") {
        assert remainder * (1 - remainder) = 0;
        tempvar underflow_check = (len - remainder) / 2;
        assert [range_check_ptr] = underflow_check;
    }
    let range_check_ptr = range_check_ptr + 1;

    let (local bytes_data) = alloc();
    tempvar i = 0;
    tempvar bytes_ptr = bytes_data;

    loop:
    let i = [ap - 2];
    let bytes_ptr = cast([ap - 1], felt*);
    let x_ptr = cast([fp - 3], BytesStruct*);

    // Combine two nibbles into a byte: (high_nibble * 16 + low_nibble)
    assert [bytes_ptr] = 16 * x_ptr.data[i] + x_ptr.data[i + 1];

    tempvar cond = x_ptr.len - i - 2 - remainder;
    tempvar i = i + 2;
    tempvar bytes_ptr = bytes_ptr + 1;

    jmp loop if cond != 0;

    if (remainder != 0) {
        assert [bytes_ptr] = 16 * x_ptr.data[i];
    }

    // Return the result
    let final_len = (len + remainder) / 2;
    tempvar result = Bytes(new BytesStruct(bytes_data, final_len));
    return result;
}

func bytes_to_nibble_list{bitwise_ptr: BitwiseBuiltin*}(bytes_: Bytes) -> Bytes {
    alloc_locals;
    local result: Bytes;

    %{ bytes_to_nibble_list_hint %}

    assert result.value.len = 2 * bytes_.value.len;

    if (bytes_.value.len == 0) {
        return bytes_;
    }

    tempvar bitwise_ptr = bitwise_ptr;
    tempvar len = bytes_.value.len;

    loop:
    let bitwise_ptr = bitwise_ptr;
    let len = [ap - 1];
    let ptr = cast([fp - 3], BytesStruct*);
    let dst = cast([fp], BytesStruct*);

    assert bitwise_ptr.x = dst.data[2 * len - 2] * 2 ** 4;
    assert bitwise_ptr.y = dst.data[2 * len - 1];
    assert bitwise_ptr.x_xor_y = ptr.data[len - 1];

    tempvar bitwise_ptr = bitwise_ptr + BitwiseBuiltin.SIZE;
    tempvar len = len - 1;

    jmp loop if len != 0;

    return result;
}

func _prepare_trie{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(
    trie_union: EthereumTries,
    storage_roots_: OptionalMappingAddressBytes32,
    hash_function_name: felt,
) -> MappingBytesBytes {
    alloc_locals;

    let (local mapping_ptr_start: BytesBytesDictAccess*) = default_dict_new(0);

    tempvar is_account = cast(trie_union.value.account.value, felt);
    jmp account if is_account != 0;

    tempvar is_storage = cast(trie_union.value.storage.value, felt);
    jmp storage if is_storage != 0;

    tempvar is_transaction = cast(trie_union.value.transaction.value, felt);
    jmp transaction if is_transaction != 0;

    tempvar is_receipt = cast(trie_union.value.receipt.value, felt);
    jmp receipt if is_receipt != 0;

    tempvar is_withdrawal = cast(trie_union.value.withdrawal.value, felt);
    jmp withdrawal if is_withdrawal != 0;

    raise('Invalid trie union');

    account:
    if (cast(storage_roots_.value, felt) == 0) {
        raise('Missing Storage Roots');
    }
    let account_trie = trie_union.value.account;
    _prepare_trie_inner_account(
        account_trie,
        account_trie.value._data.value.dict_ptr_start,
        mapping_ptr_start,
        MappingAddressBytes32(storage_roots_.value),
        hash_function_name,
    );
    jmp end;

    storage:
    let storage_trie = trie_union.value.storage;
    _prepare_trie_inner_storage(
        storage_trie,
        storage_trie.value._data.value.dict_ptr_start,
        mapping_ptr_start,
        hash_function_name,
    );
    jmp end;

    transaction:
    let transaction_trie = trie_union.value.transaction;
    _prepare_trie_inner_transaction(
        transaction_trie,
        transaction_trie.value._data.value.dict_ptr_start,
        mapping_ptr_start,
        hash_function_name,
    );
    jmp end;

    receipt:
    let receipt_trie = trie_union.value.receipt;
    _prepare_trie_inner_receipt(
        receipt_trie,
        receipt_trie.value._data.value.dict_ptr_start,
        mapping_ptr_start,
        hash_function_name,
    );
    jmp end;

    withdrawal:
    let withdrawal_trie = trie_union.value.withdrawal;
    _prepare_trie_inner_withdrawal(
        withdrawal_trie,
        withdrawal_trie.value._data.value.dict_ptr_start,
        mapping_ptr_start,
        hash_function_name,
    );
    jmp end;

    end:
    let range_check_ptr = [ap - 6];
    let bitwise_ptr = cast([ap - 5], BitwiseBuiltin*);
    let keccak_ptr = cast([ap - 4], KeccakBuiltin*);
    let poseidon_ptr = cast([ap - 3], PoseidonBuiltin*);
    let blake2s_ptr = cast([ap - 2], felt*);
    let mapping_ptr_end = cast([ap - 1], BytesBytesDictAccess*);

    // The mapping will no longer be mutated (read or write) - as we'll only be iterating over the segment.
    let (squashed_ptr_start, squashed_ptr_end) = default_dict_finalize(
        cast(mapping_ptr_start, DictAccess*), cast(mapping_ptr_end, DictAccess*), 0
    );

    tempvar result = MappingBytesBytes(
        new MappingBytesBytesStruct(
            cast(squashed_ptr_start, BytesBytesDictAccess*),
            cast(squashed_ptr_end, BytesBytesDictAccess*),
            cast(0, MappingBytesBytesStruct*),
        ),
    );

    return result;
}

func _prepare_trie_inner_account{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(
    trie: TrieAddressOptionalAccount,
    dict_ptr: AddressAccountDictAccess*,
    mapping_ptr_end: BytesBytesDictAccess*,
    storage_roots_: MappingAddressBytes32,
    hash_function_name: felt,
) -> BytesBytesDictAccess* {
    alloc_locals;

    if (dict_ptr == trie.value._data.value.dict_ptr) {
        return mapping_ptr_end;
    }

    // Skip all None values, which are deleted trie entries
    if (cast(dict_ptr.new_value.value, felt) == 0) {
        return _prepare_trie_inner_account(
            trie,
            dict_ptr + AddressAccountDictAccess.SIZE,
            mapping_ptr_end,
            storage_roots_,
            hash_function_name,
        );
    }

    let storage_root = mapping_address_bytes32_read{mapping=storage_roots_}(dict_ptr.key);
    let preimage = Bytes20_to_Bytes(dict_ptr.key);
    let value = dict_ptr.new_value;

    let (buffer: felt*) = alloc();
    tempvar node = Node(
        new NodeEnum(
            account=value,
            bytes=Bytes(cast(0, BytesStruct*)),
            legacy_transaction=LegacyTransaction(cast(0, LegacyTransactionStruct*)),
            receipt=Receipt(cast(0, ReceiptStruct*)),
            uint=cast(0, Uint*),
            u256=U256(cast(0, U256Struct*)),
            withdrawal=Withdrawal(cast(0, WithdrawalStruct*)),
        ),
    );
    let storage_root_bytes = Bytes32_to_Bytes(storage_root);
    let encoded_value = encode_node(node, storage_root_bytes);

    if (encoded_value.value.len == 0) {
        raise('AssertionError');
    }

    // TODO: Common part, factorise.

    if (trie.value.secured.value != 0) {
        let key_bytes32 = hash_with(preimage, hash_function_name);
        let key_bytes = Bytes32_to_Bytes(key_bytes32);
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar keccak_ptr = keccak_ptr;
        tempvar blake2s_ptr = blake2s_ptr;
    } else {
        tempvar key_bytes = preimage;
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar keccak_ptr = keccak_ptr;
        tempvar blake2s_ptr = blake2s_ptr;
    }
    let key_bytes = Bytes(cast([ap - 5], BytesStruct*));
    let range_check_ptr = [ap - 4];
    let bitwise_ptr = cast([ap - 3], BitwiseBuiltin*);
    let keccak_ptr = cast([ap - 2], KeccakBuiltin*);
    let blake2s_ptr = cast([ap - 1], felt*);

    let nibbles_list = bytes_to_nibble_list(key_bytes);
    let mapping_dict_ptr = cast(mapping_ptr_end, DictAccess*);
    hashdict_write{dict_ptr=mapping_dict_ptr}(
        nibbles_list.value.len, nibbles_list.value.data, cast(encoded_value.value, felt)
    );

    return _prepare_trie_inner_account(
        trie,
        dict_ptr + AddressAccountDictAccess.SIZE,
        cast(mapping_dict_ptr, BytesBytesDictAccess*),
        storage_roots_,
        hash_function_name,
    );
}

func _prepare_trie_inner_storage{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(
    trie: TrieBytes32U256,
    dict_ptr: Bytes32U256DictAccess*,
    mapping_ptr_end: BytesBytesDictAccess*,
    hash_function_name: felt,
) -> BytesBytesDictAccess* {
    alloc_locals;

    if (dict_ptr == trie.value._data.value.dict_ptr) {
        return mapping_ptr_end;
    }

    // Skip all None values, which are deleted trie entries
    // Note: Considering that the given trie was built from the state._storage_tries of type
    // Trie[Tuple[Address, Bytes32], U256], there should not be any None values remaining.
    if (dict_ptr.new_value.value == 0) {
        return _prepare_trie_inner_storage(
            trie, dict_ptr + Bytes32U256DictAccess.SIZE, mapping_ptr_end, hash_function_name
        );
    }

    let preimage_b32 = _get_bytes32_preimage_for_key(
        dict_ptr.key.value, cast(trie.value._data.value.dict_ptr, DictAccess*)
    );
    let preimage = Bytes32_to_Bytes(preimage_b32);

    let value = dict_ptr.new_value;
    tempvar node = Node(
        new NodeEnum(
            account=Account(cast(0, AccountStruct*)),
            bytes=Bytes(cast(0, BytesStruct*)),
            legacy_transaction=LegacyTransaction(cast(0, LegacyTransactionStruct*)),
            receipt=Receipt(cast(0, ReceiptStruct*)),
            uint=cast(0, Uint*),
            u256=value,
            withdrawal=Withdrawal(cast(0, WithdrawalStruct*)),
        ),
    );
    let encoded_value = encode_node(node, Bytes(cast(0, BytesStruct*)));

    // TODO: Common part, factorise.
    if (encoded_value.value.len == 0) {
        raise('AssertionError');
    }

    if (trie.value.secured.value != 0) {
        let key_bytes32 = hash_with(preimage, hash_function_name);
        let key_bytes = Bytes32_to_Bytes(key_bytes32);
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar keccak_ptr = keccak_ptr;
        tempvar blake2s_ptr = blake2s_ptr;
    } else {
        tempvar key_bytes = preimage;
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar keccak_ptr = keccak_ptr;
        tempvar blake2s_ptr = blake2s_ptr;
    }
    let key_bytes = Bytes(cast([ap - 5], BytesStruct*));
    let range_check_ptr = [ap - 4];
    let bitwise_ptr = cast([ap - 3], BitwiseBuiltin*);
    let keccak_ptr = cast([ap - 2], KeccakBuiltin*);
    let blake2s_ptr = cast([ap - 1], felt*);

    let nibbles_list = bytes_to_nibble_list(key_bytes);
    let mapping_dict_ptr = cast(mapping_ptr_end, DictAccess*);
    hashdict_write{dict_ptr=mapping_dict_ptr}(
        nibbles_list.value.len, nibbles_list.value.data, cast(encoded_value.value, felt)
    );

    return _prepare_trie_inner_storage(
        trie,
        dict_ptr + Bytes32U256DictAccess.SIZE,
        cast(mapping_dict_ptr, BytesBytesDictAccess*),
        hash_function_name,
    );
}

func _prepare_trie_inner_transaction{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(
    trie: TrieBytesOptionalUnionBytesLegacyTransaction,
    dict_ptr: BytesOptionalUnionBytesLegacyTransactionDictAccess*,
    mapping_ptr_end: BytesBytesDictAccess*,
    hash_function_name: felt,
) -> BytesBytesDictAccess* {
    alloc_locals;

    if (dict_ptr == trie.value._data.value.dict_ptr) {
        return mapping_ptr_end;
    }

    let preimage = _get_bytes_preimage_for_key(
        dict_ptr.key.value, cast(trie.value._data.value.dict_ptr, DictAccess*)
    );
    let value = dict_ptr.new_value;

    // Skip all None values, which are deleted trie entries
    if (cast(dict_ptr.new_value.value, felt) == 0) {
        return _prepare_trie_inner_transaction(
            trie,
            dict_ptr + BytesOptionalUnionBytesLegacyTransactionDictAccess.SIZE,
            mapping_ptr_end,
            hash_function_name,
        );
    }

    // Create the correct node type

    if (dict_ptr.new_value.value.bytes.value != 0) {
        tempvar node = Node(
            new NodeEnum(
                account=Account(cast(0, AccountStruct*)),
                bytes=dict_ptr.new_value.value.bytes,
                legacy_transaction=LegacyTransaction(cast(0, LegacyTransactionStruct*)),
                receipt=Receipt(cast(0, ReceiptStruct*)),
                uint=cast(0, Uint*),
                u256=U256(cast(0, U256Struct*)),
                withdrawal=Withdrawal(cast(0, WithdrawalStruct*)),
            ),
        );
    } else {
        tempvar node = Node(
            new NodeEnum(
                account=Account(cast(0, AccountStruct*)),
                bytes=Bytes(cast(0, BytesStruct*)),
                legacy_transaction=dict_ptr.new_value.value.legacy_transaction,
                receipt=Receipt(cast(0, ReceiptStruct*)),
                uint=cast(0, Uint*),
                u256=U256(cast(0, U256Struct*)),
                withdrawal=Withdrawal(cast(0, WithdrawalStruct*)),
            ),
        );
    }

    let encoded_value = encode_node(node, Bytes(cast(0, BytesStruct*)));

    if (encoded_value.value.len == 0) {
        raise('AssertionError');
    }

    if (trie.value.secured.value != 0) {
        let key_bytes32 = hash_with(preimage, hash_function_name);
        let key_bytes = Bytes32_to_Bytes(key_bytes32);
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar keccak_ptr = keccak_ptr;
        tempvar blake2s_ptr = blake2s_ptr;
    } else {
        tempvar key_bytes = preimage;
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar keccak_ptr = keccak_ptr;
        tempvar blake2s_ptr = blake2s_ptr;
    }
    let key_bytes = Bytes(cast([ap - 5], BytesStruct*));
    let range_check_ptr = [ap - 4];
    let bitwise_ptr = cast([ap - 3], BitwiseBuiltin*);
    let keccak_ptr = cast([ap - 2], KeccakBuiltin*);
    let blake2s_ptr = cast([ap - 1], felt*);

    let nibbles_list = bytes_to_nibble_list(key_bytes);
    let mapping_dict_ptr = cast(mapping_ptr_end, DictAccess*);
    hashdict_write{dict_ptr=mapping_dict_ptr}(
        nibbles_list.value.len, nibbles_list.value.data, cast(encoded_value.value, felt)
    );

    return _prepare_trie_inner_transaction(
        trie,
        dict_ptr + BytesOptionalUnionBytesLegacyTransactionDictAccess.SIZE,
        cast(mapping_dict_ptr, BytesBytesDictAccess*),
        hash_function_name,
    );
}

func _prepare_trie_inner_receipt{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(
    trie: TrieBytesOptionalUnionBytesReceipt,
    dict_ptr: BytesOptionalUnionBytesReceiptDictAccess*,
    mapping_ptr_end: BytesBytesDictAccess*,
    hash_function_name: felt,
) -> BytesBytesDictAccess* {
    alloc_locals;

    if (dict_ptr == trie.value._data.value.dict_ptr) {
        return mapping_ptr_end;
    }

    let preimage = _get_bytes_preimage_for_key(
        dict_ptr.key.value, cast(trie.value._data.value.dict_ptr, DictAccess*)
    );
    let value = dict_ptr.new_value;

    // Skip all None values, which are deleted trie entries
    if (cast(dict_ptr.new_value.value, felt) == 0) {
        return _prepare_trie_inner_receipt(
            trie,
            dict_ptr + BytesOptionalUnionBytesReceiptDictAccess.SIZE,
            mapping_ptr_end,
            hash_function_name,
        );
    }

    // Create the correct node type

    if (dict_ptr.new_value.value.bytes.value != 0) {
        tempvar node = Node(
            new NodeEnum(
                account=Account(cast(0, AccountStruct*)),
                bytes=dict_ptr.new_value.value.bytes,
                legacy_transaction=LegacyTransaction(cast(0, LegacyTransactionStruct*)),
                receipt=Receipt(cast(0, ReceiptStruct*)),
                uint=cast(0, Uint*),
                u256=U256(cast(0, U256Struct*)),
                withdrawal=Withdrawal(cast(0, WithdrawalStruct*)),
            ),
        );
    } else {
        tempvar node = Node(
            new NodeEnum(
                account=Account(cast(0, AccountStruct*)),
                bytes=Bytes(cast(0, BytesStruct*)),
                legacy_transaction=LegacyTransaction(cast(0, LegacyTransactionStruct*)),
                receipt=dict_ptr.new_value.value.receipt,
                uint=cast(0, Uint*),
                u256=U256(cast(0, U256Struct*)),
                withdrawal=Withdrawal(cast(0, WithdrawalStruct*)),
            ),
        );
    }

    let encoded_value = encode_node(node, Bytes(cast(0, BytesStruct*)));

    if (encoded_value.value.len == 0) {
        raise('AssertionError');
    }

    if (trie.value.secured.value != 0) {
        let key_bytes32 = hash_with(preimage, hash_function_name);
        let key_bytes = Bytes32_to_Bytes(key_bytes32);
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar keccak_ptr = keccak_ptr;
        tempvar blake2s_ptr = blake2s_ptr;
    } else {
        tempvar key_bytes = preimage;
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar keccak_ptr = keccak_ptr;
        tempvar blake2s_ptr = blake2s_ptr;
    }
    let key_bytes = Bytes(cast([ap - 5], BytesStruct*));
    let range_check_ptr = [ap - 4];
    let bitwise_ptr = cast([ap - 3], BitwiseBuiltin*);
    let keccak_ptr = cast([ap - 2], KeccakBuiltin*);
    let blake2s_ptr = cast([ap - 1], felt*);

    let nibbles_list = bytes_to_nibble_list(key_bytes);
    let mapping_dict_ptr = cast(mapping_ptr_end, DictAccess*);
    hashdict_write{dict_ptr=mapping_dict_ptr}(
        nibbles_list.value.len, nibbles_list.value.data, cast(encoded_value.value, felt)
    );

    return _prepare_trie_inner_receipt(
        trie,
        dict_ptr + BytesOptionalUnionBytesReceiptDictAccess.SIZE,
        cast(mapping_dict_ptr, BytesBytesDictAccess*),
        hash_function_name,
    );
}

func _prepare_trie_inner_withdrawal{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(
    trie: TrieBytesOptionalUnionBytesWithdrawal,
    dict_ptr: BytesOptionalUnionBytesWithdrawalDictAccess*,
    mapping_ptr_end: BytesBytesDictAccess*,
    hash_function_name: felt,
) -> BytesBytesDictAccess* {
    alloc_locals;

    if (dict_ptr == trie.value._data.value.dict_ptr) {
        return mapping_ptr_end;
    }

    let preimage = _get_bytes_preimage_for_key(
        dict_ptr.key.value, cast(trie.value._data.value.dict_ptr, DictAccess*)
    );
    let value = dict_ptr.new_value;

    // Skip all None values, which are deleted trie entries
    if (cast(dict_ptr.new_value.value, felt) == 0) {
        return _prepare_trie_inner_withdrawal(
            trie,
            dict_ptr + BytesOptionalUnionBytesWithdrawalDictAccess.SIZE,
            mapping_ptr_end,
            hash_function_name,
        );
    }

    // Create the correct node type
    if (dict_ptr.new_value.value.bytes.value != 0) {
        tempvar node = Node(
            new NodeEnum(
                account=Account(cast(0, AccountStruct*)),
                bytes=dict_ptr.new_value.value.bytes,
                legacy_transaction=LegacyTransaction(cast(0, LegacyTransactionStruct*)),
                receipt=Receipt(cast(0, ReceiptStruct*)),
                uint=cast(0, Uint*),
                u256=U256(cast(0, U256Struct*)),
                withdrawal=Withdrawal(cast(0, WithdrawalStruct*)),
            ),
        );
    } else {
        tempvar node = Node(
            new NodeEnum(
                account=Account(cast(0, AccountStruct*)),
                bytes=Bytes(cast(0, BytesStruct*)),
                legacy_transaction=LegacyTransaction(cast(0, LegacyTransactionStruct*)),
                receipt=Receipt(cast(0, ReceiptStruct*)),
                uint=cast(0, Uint*),
                u256=U256(cast(0, U256Struct*)),
                withdrawal=dict_ptr.new_value.value.withdrawal,
            ),
        );
    }

    let encoded_value = encode_node(node, Bytes(cast(0, BytesStruct*)));

    if (encoded_value.value.len == 0) {
        raise('AssertionError');
    }

    if (trie.value.secured.value != 0) {
        let key_bytes32 = hash_with(preimage, hash_function_name);
        let key_bytes = Bytes32_to_Bytes(key_bytes32);
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar keccak_ptr = keccak_ptr;
        tempvar blake2s_ptr = blake2s_ptr;
    } else {
        tempvar key_bytes = preimage;
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar keccak_ptr = keccak_ptr;
        tempvar blake2s_ptr = blake2s_ptr;
    }
    let key_bytes = Bytes(cast([ap - 5], BytesStruct*));
    let range_check_ptr = [ap - 4];
    let bitwise_ptr = cast([ap - 3], BitwiseBuiltin*);
    let keccak_ptr = cast([ap - 2], KeccakBuiltin*);
    let blake2s_ptr = cast([ap - 1], felt*);

    let nibbles_list = bytes_to_nibble_list(key_bytes);
    let mapping_dict_ptr = cast(mapping_ptr_end, DictAccess*);
    hashdict_write{dict_ptr=mapping_dict_ptr}(
        nibbles_list.value.len, nibbles_list.value.data, cast(encoded_value.value, felt)
    );

    return _prepare_trie_inner_withdrawal(
        trie,
        dict_ptr + BytesOptionalUnionBytesWithdrawalDictAccess.SIZE,
        cast(mapping_dict_ptr, BytesBytesDictAccess*),
        hash_function_name,
    );
}

func root{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(
    trie_union: EthereumTries,
    storage_roots_: OptionalMappingAddressBytes32,
    hash_function_name: felt,
) -> Root {
    alloc_locals;

    let obj = _prepare_trie(trie_union, storage_roots_, hash_function_name);
    let patricialized = patricialize(obj, Uint(0), hash_function_name);
    let root_node = encode_internal_node(patricialized, hash_function_name);
    let rlp_encoded_root_node = encode(root_node);

    let is_encoding_lt_32 = is_le(rlp_encoded_root_node.value.len, 31);
    if (is_encoding_lt_32 != 0) {
        let root_hash = hash_with(rlp_encoded_root_node, hash_function_name);
        return root_hash;
    }

    if (cast(root_node.value.bytes.value, felt) == 0) {
        raise('AssertionError');
    }
    let root_b32 = Bytes_to_Bytes32(root_node.value.bytes);
    return root_b32;
}

// Finds the maximum length of common prefix among all keys in a trie at a given level.
//
// Given a trie's key-value pairs (obj) with keys in nibble-list format, this function searches
// for the maximum length `j` such that all keys in obj share the same prefix from position level to j.
// This is used during trie construction to determine how many nibbles can be grouped into a single
// extension node.
//
// # Arguments
// ## Implicit Arguments
// * `substring` - The prefix of the current key-value pair being examined
// * `level` - The current level being examined
// * `dict_ptr_stop` - The pointer to the end of the key-value pairs being examined
//
// ## Explicit Arguments
// * `obj` - Pointer to the current key-value pair being examined
// * `current_length` - Current maximum common prefix length found so far
//
// # Returns
//
// * The length of the common prefix shared by all keys starting from `level`
// ```
func _search_common_prefix_length{
    range_check_ptr,
    substring: Bytes,
    level: Uint,
    dict_ptr_stop: BytesBytesDictAccess*,
    poseidon_ptr: PoseidonBuiltin*,
}(obj: BytesBytesDictAccess*, current_length: felt) -> felt {
    alloc_locals;
    if (obj == dict_ptr_stop) {
        return current_length;
    }

    let preimage = _get_bytes_preimage_for_key(obj.key.value, cast(dict_ptr_stop, DictAccess*));
    tempvar sliced_key = Bytes(
        new BytesStruct(preimage.value.data + level.value, preimage.value.len - level.value)
    );
    let result = common_prefix_length(substring, sliced_key);
    let current_length = min(result, current_length);
    if (current_length == 0) {
        return 0;
    }

    return _search_common_prefix_length(obj + BytesBytesDictAccess.SIZE, current_length);
}

func _get_branch_for_nibble_at_level_inner{poseidon_ptr: PoseidonBuiltin*}(
    dict_ptr: BytesBytesDictAccess*,
    dict_ptr_stop: BytesBytesDictAccess*,
    branch_ptr: BytesBytesDictAccess*,
    nibble: felt,
    level: felt,
    value: Bytes,
) -> (BytesBytesDictAccess*, Bytes) {
    alloc_locals;
    if (dict_ptr == dict_ptr_stop) {
        return (branch_ptr, value);
    }

    let preimage = _get_bytes_preimage_for_key(
        dict_ptr.key.value, cast(dict_ptr_stop, DictAccess*)
    );

    // Check cases
    let is_value_case = is_zero(preimage.value.len - level);
    if (is_value_case != 0) {
        // Value case - update value and continue
        return _get_branch_for_nibble_at_level_inner(
            dict_ptr + BytesBytesDictAccess.SIZE,
            dict_ptr_stop,
            branch_ptr,
            nibble,
            level,
            dict_ptr.new_value,
        );
    }

    let is_nibble_case = is_zero(preimage.value.data[level] - nibble);
    if (is_nibble_case != 0) {
        // Nibble case - copy entry and continue
        assert [branch_ptr].key = dict_ptr.key;
        assert [branch_ptr].prev_value = dict_ptr.prev_value;
        assert [branch_ptr].new_value = dict_ptr.new_value;

        // Copy the entry from the dict_ptr's tracker to the branch_ptr's tracker
        let source_key = dict_ptr.key.value;
        let source_ptr_stop = dict_ptr_stop;
        let dest_ptr = branch_ptr;
        %{ copy_hashdict_tracker_entry %}

        return _get_branch_for_nibble_at_level_inner(
            dict_ptr + BytesBytesDictAccess.SIZE,
            dict_ptr_stop,
            branch_ptr + BytesBytesDictAccess.SIZE,
            nibble,
            level,
            value,
        );
    }

    // Not nibble case - skip entry and continue
    return _get_branch_for_nibble_at_level_inner(
        dict_ptr + BytesBytesDictAccess.SIZE, dict_ptr_stop, branch_ptr, nibble, level, value
    );
}

// Creates a BranchNode's branch during the patricialization of a merkle trie for a specific nibble
// at a given level.
//
// This function filters the trie's key-value pairs to create a new mapping containing only entries
// where the key's nibble at the specified level matches the given nibble. It also identifies any
// value associated with a key that ends exactly at the given level.
// This is used to create the 16 branches of a BranchNode during the patricialization of a merkle trie.
//
// # Arguments
//
// * `obj` - The trie's key-value pairs
// * `nibble` - The nibble value (0-15) to filter for at the given level
// * `level` - The level in the trie at which to check the nibble
//
// # Returns
//
// * A tuple containing:
//   * The filtered mapping containing only key-value pairs where key[level] == nibble
//   * The value associated with any key that ends exactly at the given level, or an empty Bytes if none exists
func _get_branch_for_nibble_at_level{poseidon_ptr: PoseidonBuiltin*}(
    obj: MappingBytesBytes, nibble: felt, level: felt
) -> (MappingBytesBytes, Bytes) {
    alloc_locals;
    // Allocate a segment for the branch and register an associated tracker
    let (branch_start_: DictAccess*) = dict_new_empty();
    let branch_start = cast(branch_start_, BytesBytesDictAccess*);
    let dict_ptr_stop = obj.value.dict_ptr;

    tempvar empty_value = Bytes(new BytesStruct(cast(0, felt*), 0));

    // Process entries recursively
    let (branch_ptr, value) = _get_branch_for_nibble_at_level_inner(
        obj.value.dict_ptr_start, dict_ptr_stop, branch_start, nibble, level, empty_value
    );

    tempvar result = MappingBytesBytes(
        new MappingBytesBytesStruct(branch_start, branch_ptr, cast(0, MappingBytesBytesStruct*))
    );

    return (result, value);
}

// @dev Fill each of the 16 branches.
// Fill each of the 16 branches of a branch node in a Merkle Patricia Trie.
//
// Given a trie's key-value pairs (obj) with keys in nibble-list format and a level in the trie,
// splits the mapping into 16 branches based on the nibble at the given level in each key. It also
// extracts any value associated with a key that ends exactly at the given level.
//
// # Arguments
//
// * `obj` - The trie's key-value pairs
// * `level` - The level in the trie at which to split the branches (determines which nibble to use)
//
// # Returns
//
// * A tuple containing:
//   * A tuple of 16 mappings, one for each possible nibble value
func _get_branches{poseidon_ptr: PoseidonBuiltin*}(obj: MappingBytesBytes, level: Uint) -> (
    TupleMappingBytesBytes, Bytes
) {
    alloc_locals;

    let (local branches: MappingBytesBytes*) = alloc();

    local value: Bytes;
    local value_set: felt;

    let (branches_0, value_0) = _get_branch_for_nibble_at_level(obj, 0, level.value);
    assert branches[0] = branches_0;
    if (value_0.value.len != 0) {
        assert value = value_0;
        assert value_set = 1;
    }
    let (branches_1, value_1) = _get_branch_for_nibble_at_level(obj, 1, level.value);
    assert branches[1] = branches_1;
    if (value_1.value.len != 0) {
        assert value = value_1;
        assert value_set = 1;
    }
    let (branches_2, value_2) = _get_branch_for_nibble_at_level(obj, 2, level.value);
    assert branches[2] = branches_2;
    if (value_2.value.len != 0) {
        assert value = value_2;
        assert value_set = 1;
    }
    let (branches_3, value_3) = _get_branch_for_nibble_at_level(obj, 3, level.value);
    assert branches[3] = branches_3;
    if (value_3.value.len != 0) {
        assert value = value_3;
        assert value_set = 1;
    }
    let (branches_4, value_4) = _get_branch_for_nibble_at_level(obj, 4, level.value);
    assert branches[4] = branches_4;
    if (value_4.value.len != 0) {
        assert value = value_4;
        assert value_set = 1;
    }
    let (branches_5, value_5) = _get_branch_for_nibble_at_level(obj, 5, level.value);
    assert branches[5] = branches_5;
    if (value_5.value.len != 0) {
        assert value = value_5;
        assert value_set = 1;
    }
    let (branches_6, value_6) = _get_branch_for_nibble_at_level(obj, 6, level.value);
    assert branches[6] = branches_6;
    if (value_6.value.len != 0) {
        assert value = value_6;
        assert value_set = 1;
    }
    let (branches_7, value_7) = _get_branch_for_nibble_at_level(obj, 7, level.value);
    assert branches[7] = branches_7;
    if (value_7.value.len != 0) {
        assert value = value_7;
        assert value_set = 1;
    }
    let (branches_8, value_8) = _get_branch_for_nibble_at_level(obj, 8, level.value);
    assert branches[8] = branches_8;
    if (value_8.value.len != 0) {
        assert value = value_8;
        assert value_set = 1;
    }
    let (branches_9, value_9) = _get_branch_for_nibble_at_level(obj, 9, level.value);
    assert branches[9] = branches_9;
    if (value_9.value.len != 0) {
        assert value = value_9;
        assert value_set = 1;
    }
    let (branches_10, value_10) = _get_branch_for_nibble_at_level(obj, 10, level.value);
    assert branches[10] = branches_10;
    if (value_10.value.len != 0) {
        assert value = value_10;
        assert value_set = 1;
    }
    let (branches_11, value_11) = _get_branch_for_nibble_at_level(obj, 11, level.value);
    assert branches[11] = branches_11;
    if (value_11.value.len != 0) {
        assert value = value_11;
        assert value_set = 1;
    }
    let (branches_12, value_12) = _get_branch_for_nibble_at_level(obj, 12, level.value);
    assert branches[12] = branches_12;
    if (value_12.value.len != 0) {
        assert value = value_12;
        assert value_set = 1;
    }
    let (branches_13, value_13) = _get_branch_for_nibble_at_level(obj, 13, level.value);
    assert branches[13] = branches_13;
    if (value_13.value.len != 0) {
        assert value = value_13;
        assert value_set = 1;
    }
    let (branches_14, value_14) = _get_branch_for_nibble_at_level(obj, 14, level.value);
    assert branches[14] = branches_14;
    if (value_14.value.len != 0) {
        assert value = value_14;
        assert value_set = 1;
    }
    let (branches_15, value_15) = _get_branch_for_nibble_at_level(obj, 15, level.value);
    assert branches[15] = branches_15;
    if (value_15.value.len != 0) {
        assert value = value_15;
        assert value_set = 1;
    }
    %{ fp_plus_2_or_0 %}
    if (value_set != 1) {
        let (data: felt*) = alloc();
        tempvar empty_bytes = Bytes(new BytesStruct(data, 0));
        assert value = empty_bytes;
    }

    tempvar branches_tuple = TupleMappingBytesBytes(new TupleMappingBytesBytesStruct(branches, 16));
    return (branches_tuple, value);
}

func _squash_branches{range_check_ptr}(branches: TupleMappingBytesBytes) {
    alloc_locals;

    let branch_0 = branches.value.data[0].value;
    dict_squash(cast(branch_0.dict_ptr_start, DictAccess*), cast(branch_0.dict_ptr, DictAccess*));
    let branch_1 = branches.value.data[1].value;
    dict_squash(cast(branch_1.dict_ptr_start, DictAccess*), cast(branch_1.dict_ptr, DictAccess*));
    let branch_2 = branches.value.data[2].value;
    dict_squash(cast(branch_2.dict_ptr_start, DictAccess*), cast(branch_2.dict_ptr, DictAccess*));
    let branch_3 = branches.value.data[3].value;
    dict_squash(cast(branch_3.dict_ptr_start, DictAccess*), cast(branch_3.dict_ptr, DictAccess*));
    let branch_4 = branches.value.data[4].value;
    dict_squash(cast(branch_4.dict_ptr_start, DictAccess*), cast(branch_4.dict_ptr, DictAccess*));
    let branch_5 = branches.value.data[5].value;
    dict_squash(cast(branch_5.dict_ptr_start, DictAccess*), cast(branch_5.dict_ptr, DictAccess*));
    let branch_6 = branches.value.data[6].value;
    dict_squash(cast(branch_6.dict_ptr_start, DictAccess*), cast(branch_6.dict_ptr, DictAccess*));
    let branch_7 = branches.value.data[7].value;
    dict_squash(cast(branch_7.dict_ptr_start, DictAccess*), cast(branch_7.dict_ptr, DictAccess*));
    let branch_8 = branches.value.data[8].value;
    dict_squash(cast(branch_8.dict_ptr_start, DictAccess*), cast(branch_8.dict_ptr, DictAccess*));
    let branch_9 = branches.value.data[9].value;
    dict_squash(cast(branch_9.dict_ptr_start, DictAccess*), cast(branch_9.dict_ptr, DictAccess*));
    let branch_10 = branches.value.data[10].value;
    dict_squash(cast(branch_10.dict_ptr_start, DictAccess*), cast(branch_10.dict_ptr, DictAccess*));
    let branch_11 = branches.value.data[11].value;
    dict_squash(cast(branch_11.dict_ptr_start, DictAccess*), cast(branch_11.dict_ptr, DictAccess*));
    let branch_12 = branches.value.data[12].value;
    dict_squash(cast(branch_12.dict_ptr_start, DictAccess*), cast(branch_12.dict_ptr, DictAccess*));
    let branch_13 = branches.value.data[13].value;
    dict_squash(cast(branch_13.dict_ptr_start, DictAccess*), cast(branch_13.dict_ptr, DictAccess*));
    let branch_14 = branches.value.data[14].value;
    dict_squash(cast(branch_14.dict_ptr_start, DictAccess*), cast(branch_14.dict_ptr, DictAccess*));
    let branch_15 = branches.value.data[15].value;
    dict_squash(cast(branch_15.dict_ptr_start, DictAccess*), cast(branch_15.dict_ptr, DictAccess*));
    return ();
}

// @notice Given a key (inside `dict_ptr`), returns the preimage of the key registered in the tracker.
// The preimage is validated to be correctly provided by the prover by hashing it and comparing it to the key.
// @param key - The key to get the preimage for. Either a hashed or non-hashed key - but it must be a felt.
// @param dict_ptr_stop - The pointer to the end of the dict segment, the one registered in the tracker.
func _get_bytes_preimage_for_key{poseidon_ptr: PoseidonBuiltin*}(
    key: felt, dict_ptr_stop: DictAccess*
) -> Bytes {
    alloc_locals;

    // Get preimage data
    let (local preimage_data: felt*) = alloc();
    local preimage_len;
    %{ get_preimage_for_key %}

    // Verify preimage
    if (preimage_len == 1) {
        // Compare without hashing
        with_attr error_message("preimage_hash != key") {
            assert preimage_data[0] = key;
        }
        tempvar res = Bytes(new BytesStruct(preimage_data, preimage_len));
        return res;
    }

    let (preimage_hash) = poseidon_hash_many(preimage_len, preimage_data);
    with_attr error_message("preimage_hash != key") {
        assert preimage_hash = key;
    }

    tempvar res = Bytes(new BytesStruct(preimage_data, preimage_len));
    return res;
}

// @notice Given a key (inside `dict_ptr`), returns the bytes32 preimage of the key registered in the tracker.
// The preimage is validated to be correctly provided by the prover by hashing it and comparing it to the key.
// @param key - The key to get the preimage for. Either a hashed or non-hashed key - but it must be a felt.
// @param dict_ptr_stop - The pointer to the end of the dict segment, the one registered in the tracker.
func _get_bytes32_preimage_for_key{poseidon_ptr: PoseidonBuiltin*}(
    key: felt, dict_ptr_stop: DictAccess*
) -> Bytes32 {
    alloc_locals;

    // Get preimage data
    let (local preimage_data: felt*) = alloc();
    local preimage_len;
    %{ get_preimage_for_key %}

    let (preimage_hash) = poseidon_hash_many(preimage_len, preimage_data);
    with_attr error_message("preimage_hash != key") {
        assert preimage_hash = key;
    }

    tempvar res = Bytes32(new Bytes32Struct(preimage_data[0], preimage_data[1]));
    return res;
}

func get_tuple_address_bytes32_preimage_for_key{poseidon_ptr: PoseidonBuiltin*}(
    key: felt, dict_ptr_stop: DictAccess*
) -> TupleAddressBytes32 {
    alloc_locals;

    // Get preimage data
    let (local preimage_data: felt*) = alloc();
    local preimage_len;
    %{ get_preimage_for_key %}

    let (preimage_hash) = poseidon_hash_many(preimage_len, preimage_data);
    with_attr error_message("preimage_hash != key") {
        assert preimage_hash = key;
    }

    tempvar res = TupleAddressBytes32(
        new TupleAddressBytes32Struct(
            address=Address(preimage_data[0]),
            bytes32=Bytes32(new Bytes32Struct(preimage_data[1], preimage_data[2])),
        ),
    );
    return res;
}

// @dev The obj mapping needs to be squashed before calling this function.
// @dev No other squashing is required after this function returns as it only reads from the DictAccess segment.
// @dev This function could be made faster by sorting the DictAccess segment by key before processing it.
func patricialize{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(obj: MappingBytesBytes, level: Uint, hash_function_name: felt) -> InternalNode {
    alloc_locals;

    let len = (obj.value.dict_ptr - obj.value.dict_ptr_start) / BytesBytesDictAccess.SIZE;
    if (len == 0) {
        tempvar internal_node = InternalNode(cast(0, InternalNodeEnum*));
        return internal_node;
    }

    let arbitrary_value = obj.value.dict_ptr_start.new_value;
    let current_key = obj.value.dict_ptr_start.key.value;
    let preimage = _get_bytes_preimage_for_key(current_key, cast(obj.value.dict_ptr, DictAccess*));

    // if leaf node
    if (len == 1) {
        tempvar sliced_key = Bytes(
            new BytesStruct(preimage.value.data + level.value, preimage.value.len - level.value)
        );
        let extended = ExtendedImpl.bytes(arbitrary_value);
        tempvar leaf_node = LeafNode(new LeafNodeStruct(sliced_key, extended));
        let internal_node = InternalNodeImpl.leaf_node(leaf_node);
        return internal_node;
    }

    // prepare for extension node check by finding max j such that all keys in
    // obj have the same key[i:j]
    let dict_ptr_stop = obj.value.dict_ptr;
    let prefix_length = preimage.value.len - level.value;
    tempvar substring = Bytes(new BytesStruct(preimage.value.data + level.value, prefix_length));
    let prefix_length = _search_common_prefix_length{
        substring=substring, level=level, dict_ptr_stop=dict_ptr_stop
    }(obj.value.dict_ptr_start + BytesBytesDictAccess.SIZE, prefix_length);

    if (prefix_length != 0) {
        tempvar prefix = Bytes(new BytesStruct(preimage.value.data + level.value, prefix_length));
        let patricialized_subnode = patricialize(
            obj, Uint(level.value + prefix_length), hash_function_name
        );
        let encoded_subnode = encode_internal_node(patricialized_subnode, hash_function_name);
        tempvar extension_node = ExtensionNode(new ExtensionNodeStruct(prefix, encoded_subnode));
        let internal_node = InternalNodeImpl.extension_node(extension_node);
        return internal_node;
    }

    let (branches, value) = _get_branches(obj, level);
    tempvar next_level = Uint(level.value + 1);

    let patricialized_0 = patricialize(branches.value.data[0], next_level, hash_function_name);
    let encoded_0 = encode_internal_node(patricialized_0, hash_function_name);
    let patricialized_1 = patricialize(branches.value.data[1], next_level, hash_function_name);
    let encoded_1 = encode_internal_node(patricialized_1, hash_function_name);
    let patricialized_2 = patricialize(branches.value.data[2], next_level, hash_function_name);
    let encoded_2 = encode_internal_node(patricialized_2, hash_function_name);
    let patricialized_3 = patricialize(branches.value.data[3], next_level, hash_function_name);
    let encoded_3 = encode_internal_node(patricialized_3, hash_function_name);
    let patricialized_4 = patricialize(branches.value.data[4], next_level, hash_function_name);
    let encoded_4 = encode_internal_node(patricialized_4, hash_function_name);
    let patricialized_5 = patricialize(branches.value.data[5], next_level, hash_function_name);
    let encoded_5 = encode_internal_node(patricialized_5, hash_function_name);
    let patricialized_6 = patricialize(branches.value.data[6], next_level, hash_function_name);
    let encoded_6 = encode_internal_node(patricialized_6, hash_function_name);
    let patricialized_7 = patricialize(branches.value.data[7], next_level, hash_function_name);
    let encoded_7 = encode_internal_node(patricialized_7, hash_function_name);
    let patricialized_8 = patricialize(branches.value.data[8], next_level, hash_function_name);
    let encoded_8 = encode_internal_node(patricialized_8, hash_function_name);
    let patricialized_9 = patricialize(branches.value.data[9], next_level, hash_function_name);
    let encoded_9 = encode_internal_node(patricialized_9, hash_function_name);
    let patricialized_10 = patricialize(branches.value.data[10], next_level, hash_function_name);
    let encoded_10 = encode_internal_node(patricialized_10, hash_function_name);
    let patricialized_11 = patricialize(branches.value.data[11], next_level, hash_function_name);
    let encoded_11 = encode_internal_node(patricialized_11, hash_function_name);
    let patricialized_12 = patricialize(branches.value.data[12], next_level, hash_function_name);
    let encoded_12 = encode_internal_node(patricialized_12, hash_function_name);
    let patricialized_13 = patricialize(branches.value.data[13], next_level, hash_function_name);
    let encoded_13 = encode_internal_node(patricialized_13, hash_function_name);
    let patricialized_14 = patricialize(branches.value.data[14], next_level, hash_function_name);
    let encoded_14 = encode_internal_node(patricialized_14, hash_function_name);
    let patricialized_15 = patricialize(branches.value.data[15], next_level, hash_function_name);
    let encoded_15 = encode_internal_node(patricialized_15, hash_function_name);

    // Squash the dicts for all the branches
    _squash_branches(branches);

    tempvar subnodes = Subnodes(
        new SubnodesStruct(
            encoded_0,
            encoded_1,
            encoded_2,
            encoded_3,
            encoded_4,
            encoded_5,
            encoded_6,
            encoded_7,
            encoded_8,
            encoded_9,
            encoded_10,
            encoded_11,
            encoded_12,
            encoded_13,
            encoded_14,
            encoded_15,
        ),
    );
    let value_extended = ExtendedImpl.bytes(value);
    tempvar branch_node = BranchNode(new BranchNodeStruct(subnodes, value_extended));
    let internal_node = InternalNodeImpl.branch_node(branch_node);

    return internal_node;
}

// Utils function, porting this to a module would incur a lot of refactoring due to circular imports
func mapping_address_bytes32_read{range_check_ptr, mapping: MappingAddressBytes32}(
    key: Address
) -> Bytes32 {
    alloc_locals;
    let dict_ptr = cast(mapping.value.dict_ptr, DictAccess*);
    let (value_ptr) = dict_read{dict_ptr=dict_ptr}(key.value);
    let value = Bytes32(cast(value_ptr, Bytes32Struct*));
    tempvar mapping = MappingAddressBytes32(
        new MappingAddressBytes32Struct(
            mapping.value.dict_ptr_start,
            cast(dict_ptr, AddressBytes32DictAccess*),
            mapping.value.parent_dict,
        ),
    );
    return value;
}

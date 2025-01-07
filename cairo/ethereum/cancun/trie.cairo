from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.bitwise import BitwiseBuiltin
from starkware.cairo.common.dict import DictAccess
from starkware.cairo.common.cairo_builtins import KeccakBuiltin
from starkware.cairo.common.memcpy import memcpy

from src.utils.bytes import uint256_to_bytes32_little
from src.utils.dict import dict_address_read, hashdict_bytes32_read
from ethereum.crypto.hash import keccak256
from ethereum.utils.numeric import min
from ethereum.rlp import encode, _encode_bytes, _encode
from ethereum_types.numeric import U256, Uint, bool, U256Struct
from ethereum_types.bytes import (
    Bytes,
    BytesStruct,
    Bytes32,
    StringStruct,
    String,
    MappingBytesBytes,
    MappingBytesBytesStruct,
    BytesBytesDictAccess,
    TupleMappingBytesBytes,
    TupleMappingBytesBytesStruct,
)
from ethereum.cancun.blocks import Receipt, Withdrawal
from ethereum.cancun.fork_types import (
    Account,
    AccountStruct,
    Address,
    Bytes32U256DictAccess,
    MappingAddressAccount,
    MappingAddressAccountStruct,
    MappingBytes32U256,
    MappingBytes32U256Struct,
    AddressAccountDictAccess,
)
from ethereum.cancun.transactions import LegacyTransaction
from ethereum.rlp import (
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

struct LeafNodeStruct {
    rest_of_key: Bytes,
    value: Extended,
}

struct LeafNode {
    value: LeafNodeStruct*,
}

struct ExtensionNodeStruct {
    key_segment: Bytes,
    subnode: Extended,
}

struct ExtensionNode {
    value: ExtensionNodeStruct*,
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

struct BranchNodeStruct {
    subnodes: Subnodes,
    value: Extended,
}

struct BranchNode {
    value: BranchNodeStruct*,
}

struct InternalNode {
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

struct TrieAddressAccountStruct {
    secured: bool,
    default: Account,
    _data: MappingAddressAccount,
}

struct TrieAddressAccount {
    value: TrieAddressAccountStruct*,
}

struct TrieBytes32U256Struct {
    secured: bool,
    default: U256,
    _data: MappingBytes32U256,
}

struct TrieBytes32U256 {
    value: TrieBytes32U256Struct*,
}

func encode_internal_node{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*
}(node: InternalNode) -> Extended {
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

    let hash = keccak256(encoded);
    let (data) = alloc();
    uint256_to_bytes32_little(data, [hash.value]);
    let hashed = ExtendedImpl.bytes(Bytes(new BytesStruct(data, 32)));
    return hashed;
}

func encode_node{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}(
    node: Node, storage_root: Bytes
) -> Bytes {
    alloc_locals;

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
    with_attr error_message("encode_node: node cannot be None") {
        assert 0 = 1;
    }
    tempvar result = Bytes(new BytesStruct(cast(0, felt*), 0));
    return result;

    account:
    if (cast(storage_root.value, felt) == 0) {
        with_attr error_message("encode_node: account without storage root") {
            assert 0 = 1;
        }
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
    let encoded = encode_uint([node.value.uint]);
    return encoded;

    u256:
    let encoded = encode_u256(node.value.u256);
    return encoded;

    withdrawal:
    let encoded = encode_withdrawal(node.value.withdrawal);
    return encoded;
}

// func copy_trie(trie: Trie[K, V]) -> Trie[K, V] {
//     // Implementation:
//     // return Trie(trie.secured, trie.default, copy.copy(trie._data))
// }

// func trie_set(trie: Trie[K, V], key: K, value: V) {
//     // Implementation:
//     // if value == trie.default:
//     // if key in trie._data:
//     // del trie._data[key]
//     // else:
//     // trie._data[key] = value
//         // if key in trie._data:
//         // del trie._data[key]
//             // del trie._data[key]
//     // else:
//         // trie._data[key] = value
// }

func trie_get_TrieAddressAccount{trie: TrieAddressAccount}(key: Address) -> Account {
    let dict_ptr = cast(trie.value._data.value.dict_ptr, DictAccess*);

    with dict_ptr {
        let (pointer) = dict_address_read(key);
    }
    let new_dict_ptr = cast(dict_ptr, AddressAccountDictAccess*);
    tempvar mapping = MappingAddressAccount(
        new MappingAddressAccountStruct(trie.value._data.value.dict_ptr_start, new_dict_ptr)
    );
    tempvar trie = TrieAddressAccount(
        new TrieAddressAccountStruct(trie.value.secured, trie.value.default, mapping)
    );
    tempvar res = Account(cast(pointer, AccountStruct*));
    return res;
}

func trie_get_TrieBytes32U256{poseidon_ptr: PoseidonBuiltin*, trie: TrieBytes32U256}(
    key: Bytes32
) -> U256 {
    let dict_ptr = cast(trie.value._data.value.dict_ptr, DictAccess*);

    with dict_ptr {
        let (pointer) = hashdict_bytes32_read(key);
    }
    let new_dict_ptr = cast(dict_ptr, Bytes32U256DictAccess*);
    tempvar mapping = MappingBytes32U256(
        new MappingBytes32U256Struct(trie.value._data.value.dict_ptr_start, new_dict_ptr)
    );
    tempvar trie = TrieBytes32U256(
        new TrieBytes32U256Struct(trie.value.secured, trie.value.default, mapping)
    );
    tempvar res = U256(cast(pointer, U256Struct*));
    return res;
}

func common_prefix_length(a: Bytes, b: Bytes) -> felt {
    alloc_locals;
    local result;

    %{ memory[fp] = oracle(ids, reference="ethereum.cancun.trie.common_prefix_length") %}

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

    if (x.value.len == 0) {
        assert [compact] = 16 * (2 * is_leaf.value);
        tempvar result = Bytes(new BytesStruct(compact, 1));
        return result;
    }

    local remainder = nondet %{ ids.x.value.len % 2 %};
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

func bytes_to_nibble_list{bitwise_ptr: BitwiseBuiltin*}(bytes_: Bytes) -> Bytes {
    alloc_locals;
    local result: Bytes;

    %{ memory[ap - 1] = oracle(ids, reference="ethereum.cancun.trie.bytes_to_nibble_list") %}

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

// func _prepare_trie(trie: Trie[K, V], get_storage_root: Callable[List(elts=[Name(id='Address', ctx=Load())], ctx=Load()), Root]) -> Mapping[Bytes, Bytes] {
//     // Implementation:
//     // mapped: MutableMapping[Bytes, Bytes] = {}
//     // for (preimage, value) in trie._data.items():
//     // if isinstance(value, Account):
//     // assert get_storage_root is not None
//     // address = Address(preimage)
//     // encoded_value = encode_node(value, get_storage_root(address))
//     // else:
//     // encoded_value = encode_node(value)
//     // if encoded_value == b'':
//     // raise AssertionError
//     // key: Bytes
//     // if trie.secured:
//     // key = keccak256(preimage)
//     // else:
//     // key = preimage
//     // mapped[bytes_to_nibble_list(key)] = encoded_value
//         // if isinstance(value, Account):
//         // assert get_storage_root is not None
//         // address = Address(preimage)
//         // encoded_value = encode_node(value, get_storage_root(address))
//         // else:
//         // encoded_value = encode_node(value)
//             // assert get_storage_root is not None
//             // address = Address(preimage)
//             // encoded_value = encode_node(value, get_storage_root(address))
//         // else:
//             // encoded_value = encode_node(value)
//         // if encoded_value == b'':
//         // raise AssertionError
//             // raise AssertionError
//         // key: Bytes
//         // if trie.secured:
//         // key = keccak256(preimage)
//         // else:
//         // key = preimage
//             // key = keccak256(preimage)
//         // else:
//             // key = preimage
//         // mapped[bytes_to_nibble_list(key)] = encoded_value
//     // return mapped
// }

// func root(trie: Trie[K, V], get_storage_root: Callable[List(elts=[Name(id='Address', ctx=Load())], ctx=Load()), Root]) -> Root {
//     // Implementation:
//     // obj = _prepare_trie(trie, get_storage_root)
//     // root_node = encode_internal_node(patricialize(obj, Uint(0)))
//     // if len(encode(root_node)) < 32:
//     // return keccak256(encode(root_node))
//     // else:
//     // assert isinstance(root_node, Bytes)
//     // return Root(root_node)
//         // return keccak256(encode(root_node))
//     // else:
//         // assert isinstance(root_node, Bytes)
//         // return Root(root_node)
// }

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
    range_check_ptr, substring: Bytes, level: Uint, dict_ptr_stop: BytesBytesDictAccess*
}(obj: BytesBytesDictAccess*, current_length: felt) -> felt {
    alloc_locals;
    if (obj == dict_ptr_stop) {
        return current_length;
    }

    tempvar sliced_key = Bytes(
        new BytesStruct(obj.key.value.data + level.value, obj.key.value.len - level.value)
    );
    let result = common_prefix_length(substring, sliced_key);
    let current_length = min(result, current_length);
    if (current_length == 0) {
        return 0;
    }

    return _search_common_prefix_length(obj + BytesBytesDictAccess.SIZE, current_length);
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
func _get_branche_for_nibble_at_level(obj: MappingBytesBytes, nibble: felt, level: felt) -> (
    MappingBytesBytes, Bytes
) {
    alloc_locals;
    let (local branch: BytesBytesDictAccess*) = alloc();
    local dict_ptr_stop: BytesBytesDictAccess* = obj.value.dict_ptr;
    local value: Bytes;
    local value_set: felt;

    tempvar branch = branch;
    tempvar dict_ptr = obj.value.dict_ptr_start;

    loop:
    let branch = cast([ap - 2], BytesBytesDictAccess*);
    let dict_ptr = cast([ap - 1], BytesBytesDictAccess*);
    // The verifier just needs to make sure that whatever case we are in is properly asserted.
    tempvar is_nibble_case = nondet %{ memory.get(ids.dict_ptr.key.value.data + ids.level) == ids.nibble %};
    tempvar is_value_case = nondet %{ int(ids.dict_ptr.key.value.len == ids.level) %};

    static_assert branch == [ap - 4];
    static_assert dict_ptr == [ap - 3];

    jmp value_case if is_value_case != 0;
    jmp nibble_case if is_nibble_case != 0;
    jmp not_nibble_case;

    value_case:
    let branch = cast([ap - 4], BytesBytesDictAccess*);
    let dict_ptr = cast([ap - 3], BytesBytesDictAccess*);

    assert dict_ptr.key.value.len = level;
    assert value = dict_ptr.new_value;
    assert value_set = 1;

    let dict_ptr_stop = cast([fp + 1], BytesBytesDictAccess*);
    tempvar stop = (dict_ptr_stop - dict_ptr) - BytesBytesDictAccess.SIZE;
    tempvar branch = branch;
    tempvar dict_ptr = dict_ptr + BytesBytesDictAccess.SIZE;

    static_assert branch == [ap - 2];
    static_assert dict_ptr == [ap - 1];
    jmp loop if stop != 0;
    jmp end;

    // Case 1: nibble != key[level], don't include in branch
    not_nibble_case:
    let branch = cast([ap - 4], BytesBytesDictAccess*);
    let dict_ptr = cast([ap - 3], BytesBytesDictAccess*);

    assert_not_zero(dict_ptr.key.value.data[level] - nibble);

    let dict_ptr_stop = cast([fp + 1], BytesBytesDictAccess*);
    tempvar stop = (dict_ptr_stop - dict_ptr) - BytesBytesDictAccess.SIZE;
    tempvar branch = branch;
    tempvar dict_ptr = dict_ptr + BytesBytesDictAccess.SIZE;

    static_assert branch == [ap - 2];
    static_assert dict_ptr == [ap - 1];
    jmp loop if stop != 0;
    jmp end;

    // Case 2: nibble == key[level], include in branch
    nibble_case:
    let branch = cast([ap - 4], BytesBytesDictAccess*);
    let dict_ptr = cast([ap - 3], BytesBytesDictAccess*);

    assert dict_ptr.key.value.data[level] = nibble;
    assert [branch].key = dict_ptr.key;
    assert [branch].prev_value = dict_ptr.prev_value;
    assert [branch].new_value = dict_ptr.new_value;

    let dict_ptr_stop = cast([fp + 1], BytesBytesDictAccess*);
    tempvar stop = (dict_ptr_stop - dict_ptr) - BytesBytesDictAccess.SIZE;
    tempvar branch = branch + BytesBytesDictAccess.SIZE;
    tempvar dict_ptr = dict_ptr + BytesBytesDictAccess.SIZE;

    static_assert branch == [ap - 2];
    static_assert dict_ptr == [ap - 1];
    jmp loop if stop != 0;
    jmp end;

    end:
    let branche_stop = cast([ap - 2], BytesBytesDictAccess*);
    let branche_start = cast([fp], BytesBytesDictAccess*);
    let value = Bytes(cast([fp + 2], BytesStruct*));
    let value_set = [fp + 3];

    // Fill value_set if it's not set yet. This is just to be able to test against 1
    // as this would raise if the memory is empty.
    %{ ids.value_set = memory.get(fp + 3) or 0 %}
    if (value_set != 1) {
        let (data: felt*) = alloc();
        tempvar empty_bytes = Bytes(new BytesStruct(data, 0));
        assert value = empty_bytes;
    }

    tempvar result = MappingBytesBytes(new MappingBytesBytesStruct(branche_start, branche_stop));
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
func _get_branches(obj: MappingBytesBytes, level: Uint) -> (TupleMappingBytesBytes, Bytes) {
    alloc_locals;

    let (local branches: MappingBytesBytes*) = alloc();
    local value: Bytes;
    local value_set: felt;

    let (branches_0, value_0) = _get_branche_for_nibble_at_level(obj, 0, level.value);
    assert branches[0] = branches_0;
    if (value_0.value.len != 0) {
        assert value = value_0;
        assert value_set = 1;
    }
    let (branches_1, value_1) = _get_branche_for_nibble_at_level(obj, 1, level.value);
    assert branches[1] = branches_1;
    if (value_1.value.len != 0) {
        assert value = value_1;
        assert value_set = 1;
    }
    let (branches_2, value_2) = _get_branche_for_nibble_at_level(obj, 2, level.value);
    assert branches[2] = branches_2;
    if (value_2.value.len != 0) {
        assert value = value_2;
        assert value_set = 1;
    }
    let (branches_3, value_3) = _get_branche_for_nibble_at_level(obj, 3, level.value);
    assert branches[3] = branches_3;
    if (value_3.value.len != 0) {
        assert value = value_3;
        assert value_set = 1;
    }
    let (branches_4, value_4) = _get_branche_for_nibble_at_level(obj, 4, level.value);
    assert branches[4] = branches_4;
    if (value_4.value.len != 0) {
        assert value = value_4;
        assert value_set = 1;
    }
    let (branches_5, value_5) = _get_branche_for_nibble_at_level(obj, 5, level.value);
    assert branches[5] = branches_5;
    if (value_5.value.len != 0) {
        assert value = value_5;
        assert value_set = 1;
    }
    let (branches_6, value_6) = _get_branche_for_nibble_at_level(obj, 6, level.value);
    assert branches[6] = branches_6;
    if (value_6.value.len != 0) {
        assert value = value_6;
        assert value_set = 1;
    }
    let (branches_7, value_7) = _get_branche_for_nibble_at_level(obj, 7, level.value);
    assert branches[7] = branches_7;
    if (value_7.value.len != 0) {
        assert value = value_7;
        assert value_set = 1;
    }
    let (branches_8, value_8) = _get_branche_for_nibble_at_level(obj, 8, level.value);
    assert branches[8] = branches_8;
    if (value_8.value.len != 0) {
        assert value = value_8;
        assert value_set = 1;
    }
    let (branches_9, value_9) = _get_branche_for_nibble_at_level(obj, 9, level.value);
    assert branches[9] = branches_9;
    if (value_9.value.len != 0) {
        assert value = value_9;
        assert value_set = 1;
    }
    let (branches_10, value_10) = _get_branche_for_nibble_at_level(obj, 10, level.value);
    assert branches[10] = branches_10;
    if (value_10.value.len != 0) {
        assert value = value_10;
        assert value_set = 1;
    }
    let (branches_11, value_11) = _get_branche_for_nibble_at_level(obj, 11, level.value);
    assert branches[11] = branches_11;
    if (value_11.value.len != 0) {
        assert value = value_11;
        assert value_set = 1;
    }
    let (branches_12, value_12) = _get_branche_for_nibble_at_level(obj, 12, level.value);
    assert branches[12] = branches_12;
    if (value_12.value.len != 0) {
        assert value = value_12;
        assert value_set = 1;
    }
    let (branches_13, value_13) = _get_branche_for_nibble_at_level(obj, 13, level.value);
    assert branches[13] = branches_13;
    if (value_13.value.len != 0) {
        assert value = value_13;
        assert value_set = 1;
    }
    let (branches_14, value_14) = _get_branche_for_nibble_at_level(obj, 14, level.value);
    assert branches[14] = branches_14;
    if (value_14.value.len != 0) {
        assert value = value_14;
        assert value_set = 1;
    }
    let (branches_15, value_15) = _get_branche_for_nibble_at_level(obj, 15, level.value);
    assert branches[15] = branches_15;
    if (value_15.value.len != 0) {
        assert value = value_15;
        assert value_set = 1;
    }
    %{ ids.value_set = memory.get(fp + 2) or 0 %}
    if (value_set != 1) {
        let (data: felt*) = alloc();
        tempvar empty_bytes = Bytes(new BytesStruct(data, 0));
        assert value = empty_bytes;
    }

    tempvar branches_tuple = TupleMappingBytesBytes(new TupleMappingBytesBytesStruct(branches, 16));
    return (branches_tuple, value);
}

// @dev The obj mapping needs to be squashed before calling this function.
// @dev No other squashing is required after this function returns as it only reads from the DictAccess segment.
// @dev This function could be made faster by sorting the DictAccess segment by key before processing it.
func patricialize{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}(
    obj: MappingBytesBytes, level: Uint
) -> InternalNode {
    alloc_locals;

    let len = (obj.value.dict_ptr - obj.value.dict_ptr_start) / BytesBytesDictAccess.SIZE;
    if (len == 0) {
        tempvar internal_node = InternalNode(cast(0, InternalNodeEnum*));
        return internal_node;
    }

    let arbitrary_key = obj.value.dict_ptr_start.key;
    let arbitrary_value = obj.value.dict_ptr_start.new_value;

    // if leaf node
    if (len == 1) {
        tempvar sliced_key = Bytes(
            new BytesStruct(
                arbitrary_key.value.data + level.value, arbitrary_key.value.len - level.value
            ),
        );
        let extended = ExtendedImpl.bytes(arbitrary_value);
        tempvar leaf_node = LeafNode(new LeafNodeStruct(sliced_key, extended));
        let internal_node = InternalNodeImpl.leaf_node(leaf_node);
        return internal_node;
    }

    // prepare for extension node check by finding max j such that all keys in
    // obj have the same key[i:j]
    let dict_ptr_stop = obj.value.dict_ptr;
    let prefix_length = arbitrary_key.value.len - level.value;
    tempvar substring = Bytes(
        new BytesStruct(arbitrary_key.value.data + level.value, prefix_length)
    );
    let prefix_length = _search_common_prefix_length{
        substring=substring, level=level, dict_ptr_stop=dict_ptr_stop
    }(obj.value.dict_ptr_start + BytesBytesDictAccess.SIZE, prefix_length);

    if (prefix_length != 0) {
        tempvar prefix = Bytes(
            new BytesStruct(arbitrary_key.value.data + level.value, prefix_length)
        );
        let patricialized_subnode = patricialize(obj, Uint(level.value + prefix_length));
        let encoded_subnode = encode_internal_node(patricialized_subnode);
        tempvar extension_node = ExtensionNode(new ExtensionNodeStruct(prefix, encoded_subnode));
        let internal_node = InternalNodeImpl.extension_node(extension_node);
        return internal_node;
    }

    let (branches, value) = _get_branches(obj, level);
    tempvar next_level = Uint(level.value + 1);

    let patricialized_0 = patricialize(branches.value.data[0], next_level);
    let encoded_0 = encode_internal_node(patricialized_0);
    let patricialized_1 = patricialize(branches.value.data[1], next_level);
    let encoded_1 = encode_internal_node(patricialized_1);
    let patricialized_2 = patricialize(branches.value.data[2], next_level);
    let encoded_2 = encode_internal_node(patricialized_2);
    let patricialized_3 = patricialize(branches.value.data[3], next_level);
    let encoded_3 = encode_internal_node(patricialized_3);
    let patricialized_4 = patricialize(branches.value.data[4], next_level);
    let encoded_4 = encode_internal_node(patricialized_4);
    let patricialized_5 = patricialize(branches.value.data[5], next_level);
    let encoded_5 = encode_internal_node(patricialized_5);
    let patricialized_6 = patricialize(branches.value.data[6], next_level);
    let encoded_6 = encode_internal_node(patricialized_6);
    let patricialized_7 = patricialize(branches.value.data[7], next_level);
    let encoded_7 = encode_internal_node(patricialized_7);
    let patricialized_8 = patricialize(branches.value.data[8], next_level);
    let encoded_8 = encode_internal_node(patricialized_8);
    let patricialized_9 = patricialize(branches.value.data[9], next_level);
    let encoded_9 = encode_internal_node(patricialized_9);
    let patricialized_10 = patricialize(branches.value.data[10], next_level);
    let encoded_10 = encode_internal_node(patricialized_10);
    let patricialized_11 = patricialize(branches.value.data[11], next_level);
    let encoded_11 = encode_internal_node(patricialized_11);
    let patricialized_12 = patricialize(branches.value.data[12], next_level);
    let encoded_12 = encode_internal_node(patricialized_12);
    let patricialized_13 = patricialize(branches.value.data[13], next_level);
    let encoded_13 = encode_internal_node(patricialized_13);
    let patricialized_14 = patricialize(branches.value.data[14], next_level);
    let encoded_14 = encode_internal_node(patricialized_14);
    let patricialized_15 = patricialize(branches.value.data[15], next_level);
    let encoded_15 = encode_internal_node(patricialized_15);

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

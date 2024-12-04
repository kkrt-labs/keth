from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.bitwise import BitwiseBuiltin
from starkware.cairo.common.cairo_builtins import KeccakBuiltin
from starkware.cairo.common.memcpy import memcpy

from src.utils.bytes import uint256_to_bytes32_little
from ethereum.crypto.hash import keccak256
from ethereum.rlp import encode, _encode_bytes, _encode
from ethereum.base_types import U256, Bytes, Uint, BytesStruct, bool, StringStruct, String
from ethereum.cancun.blocks import Receipt, Withdrawal
from ethereum.cancun.fork_types import Account, Address, Root
from ethereum.cancun.transactions import LegacyTransaction
from ethereum.rlp import (
    Extended,
    SequenceExtended,
    SequenceExtendedStruct,
    ExtendedEnum,
    ExtendedImpl,
    encode_account,
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

struct BranchNodeStruct {
    subnodes: SequenceExtended,
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

struct NodeEnum {
    account: Account,
    bytes: Bytes,
    legacy_transaction: LegacyTransaction,
    receipt: Receipt,
    uint: Uint,
    u256: U256,
    withdrawal: Withdrawal,
}

struct Node {
    value: NodeEnum*,
}

// struct TrieStruct {
//     secured: bool,
//     default: V,
//     _data: Dict[K, V],
// }

func encode_internal_node{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*
}(node: InternalNode) -> Extended {
    alloc_locals;

    local unencoded: Extended;

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
    jmp common;

    branch_node:
    let (value: Extended*) = alloc();
    let len = node.value.branch_node.value.subnodes.value.len;
    memcpy(value, node.value.branch_node.value.subnodes.value.value, len);
    assert [value + len] = node.value.branch_node.value.value;
    tempvar sequence = SequenceExtended(new SequenceExtendedStruct(value, len + 1));
    let unencoded_ = ExtendedImpl.sequence(sequence);
    assert unencoded = unencoded_;
    jmp common;

    common:
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

// func encode_node(node: Node, storage_root: Bytes) -> Bytes {
//     // Implementation:
//     // if isinstance(node, Account):
//     // assert storage_root is not None
//     // return encode_account(node, storage_root)
//     // elif isinstance(node, (LegacyTransaction, Receipt, Withdrawal, U256)):
//     // return encode(node)
//     // elif isinstance(node, Bytes):
//     // return node
//     // else:
//     // return previous_trie.encode_node(node, storage_root)
//         // assert storage_root is not None
//         // return encode_account(node, storage_root)
//     // else:
//         // if isinstance(node, (LegacyTransaction, Receipt, Withdrawal, U256)):
//         // return encode(node)
//         // elif isinstance(node, Bytes):
//         // return node
//         // else:
//         // return previous_trie.encode_node(node, storage_root)
//             // return encode(node)
//         // else:
//             // if isinstance(node, Bytes):
//             // return node
//             // else:
//             // return previous_trie.encode_node(node, storage_root)
//                 // return node
//             // else:
//                 // return previous_trie.encode_node(node, storage_root)
// }

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

// func trie_get(trie: Trie[K, V], key: K) -> V {
//     // Implementation:
//     // return trie._data.get(key, trie.default)
// }

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

func nibble_list_to_compact(x: Bytes, is_leaf: bool) -> Bytes {
    alloc_locals;
    let (local compact) = alloc();

    if (x.value.len == 0) {
        assert [compact] = 16 * (2 * is_leaf.value);
        tempvar result = Bytes(new BytesStruct(compact, 1));
        return result;
    }

    local remainder = nondet %{ ids.x.value.len % 2 %};
    assert remainder * (1 - remainder) = 0;
    assert [compact] = 16 * (2 * is_leaf.value + remainder) + x.value.data[0] * remainder;

    if (x.value.len == remainder) {
        tempvar result = Bytes(new BytesStruct(compact, 1));
        return result;
    }

    tempvar compact = compact + 1;
    tempvar i = remainder;

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

// func patricialize(obj: Mapping[Bytes, Bytes], level: Uint) -> InternalNode {
//     // Implementation:
//     // if len(obj) == 0:
//     // return None
//         // return None
//     // arbitrary_key = next(iter(obj))
//     // if len(obj) == 1:
//     // leaf = LeafNode(arbitrary_key[level:], obj[arbitrary_key])
//     // return leaf
//         // leaf = LeafNode(arbitrary_key[level:], obj[arbitrary_key])
//         // return leaf
//     // substring = arbitrary_key[level:]
//     // prefix_length = len(substring)
//     // for key in obj:
//     // prefix_length = min(prefix_length, common_prefix_length(substring, key[level:]))
//     // if prefix_length == 0:
//     // break
//         // prefix_length = min(prefix_length, common_prefix_length(substring, key[level:]))
//         // if prefix_length == 0:
//         // break
//             // break
//     // if prefix_length > 0:
//     // prefix = arbitrary_key[level:level + prefix_length]
//     // return ExtensionNode(prefix, encode_internal_node(patricialize(obj, level + prefix_length)))
//         // prefix = arbitrary_key[level:level + prefix_length]
//         // return ExtensionNode(prefix, encode_internal_node(patricialize(obj, level + prefix_length)))
//     // branches: List[MutableMapping[Bytes, Bytes]] = []
//     // for _ in range(16):
//     // branches.append({})
//         // branches.append({})
//     // value = b''
//     // for key in obj:
//     // if len(key) == level:
//     // if isinstance(obj[key], (Account, Receipt, Uint)):
//     // raise AssertionError
//     // value = obj[key]
//     // else:
//     // branches[key[level]][key] = obj[key]
//         // if len(key) == level:
//         // if isinstance(obj[key], (Account, Receipt, Uint)):
//         // raise AssertionError
//         // value = obj[key]
//         // else:
//         // branches[key[level]][key] = obj[key]
//             // if isinstance(obj[key], (Account, Receipt, Uint)):
//             // raise AssertionError
//                 // raise AssertionError
//             // value = obj[key]
//         // else:
//             // branches[key[level]][key] = obj[key]
//     // return BranchNode([encode_internal_node(patricialize(branches[k], level + 1)) for k in range(16)], value)
// }

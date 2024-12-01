from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bitwise import BitwiseBuiltin

from ethereum.crypto.hash import keccak256
from ethereum.rlp import encode
from ethereum.base_types import U256, Bytes, Uint, BytesStruct, bool
from ethereum.cancun.blocks import Receipt, Withdrawal
from ethereum.cancun.fork_types import Account, Address, Root, encode_account
from ethereum.cancun.transactions import LegacyTransaction

from ethereum.utils.numeric import divmod

// struct LeafNode {
//     rest_of_key: Bytes,
//     value: rlp.Extended,
// }

// struct ExtensionNode {
//     key_segment: Bytes,
//     subnode: rlp.Extended,
// }

// struct BranchNode {
//     subnodes: rlp.Extended,
//     value: rlp.Extended,
// }

// struct Trie {
//     secured: bool,
//     default: V,
//     _data: Dict[K, V],
// }

// func encode_internal_node(node: InternalNode) -> rlp.Extended {
//     // Implementation:
//     // unencoded: rlp.Extended
//     // if node is None:
//     // unencoded = b''
//     // elif isinstance(node, LeafNode):
//     // unencoded = (nibble_list_to_compact(node.rest_of_key, True), node.value)
//     // elif isinstance(node, ExtensionNode):
//     // unencoded = (nibble_list_to_compact(node.key_segment, False), node.subnode)
//     // elif isinstance(node, BranchNode):
//     // unencoded = node.subnodes + [node.value]
//     // else:
//     // raise AssertionError(f'Invalid internal node type {type(node)}!')
//         // unencoded = b''
//     // else:
//         // if isinstance(node, LeafNode):
//         // unencoded = (nibble_list_to_compact(node.rest_of_key, True), node.value)
//         // elif isinstance(node, ExtensionNode):
//         // unencoded = (nibble_list_to_compact(node.key_segment, False), node.subnode)
//         // elif isinstance(node, BranchNode):
//         // unencoded = node.subnodes + [node.value]
//         // else:
//         // raise AssertionError(f'Invalid internal node type {type(node)}!')
//             // unencoded = (nibble_list_to_compact(node.rest_of_key, True), node.value)
//         // else:
//             // if isinstance(node, ExtensionNode):
//             // unencoded = (nibble_list_to_compact(node.key_segment, False), node.subnode)
//             // elif isinstance(node, BranchNode):
//             // unencoded = node.subnodes + [node.value]
//             // else:
//             // raise AssertionError(f'Invalid internal node type {type(node)}!')
//                 // unencoded = (nibble_list_to_compact(node.key_segment, False), node.subnode)
//             // else:
//                 // if isinstance(node, BranchNode):
//                 // unencoded = node.subnodes + [node.value]
//                 // else:
//                 // raise AssertionError(f'Invalid internal node type {type(node)}!')
//                     // unencoded = node.subnodes + [node.value]
//                 // else:
//                     // raise AssertionError(f'Invalid internal node type {type(node)}!')
//     // encoded = encode(unencoded)
//     // if len(encoded) < 32:
//     // return unencoded
//     // else:
//     // return keccak256(encoded)
//         // return unencoded
//     // else:
//         // return keccak256(encoded)
// }

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

// func common_prefix_length(a: Sequence, b: Sequence) -> felt {
//     // Implementation:
//     // for i in range(len(a)):
//     // if i >= len(b) or a[i] != b[i]:
//     // return i
//         // if i >= len(b) or a[i] != b[i]:
//         // return i
//             // return i
//     // return len(a)
// }

func nibble_list_to_compact{range_check_ptr}(x: Bytes, is_leaf: bool) -> Bytes {
    alloc_locals;
    let (local compact) = alloc();

    let (_, local remainder) = divmod(x.value.len, 2);
    if (remainder == 0) {
        assert [compact] = 16 * (2 * is_leaf.value);
    } else {
        assert [compact] = 16 * (2 * is_leaf.value + 1) + x.value.data[0];
    }

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

    let (len, r) = divmod(i - remainder, 2);
    assert r = 0;

    let compact = cast([fp], felt*);
    tempvar result = Bytes(new BytesStruct(compact, 1 + len));
    return result;
}

func bytes_to_nibble_list{bitwise_ptr: BitwiseBuiltin*}(bytes_: Bytes) -> Bytes {
    alloc_locals;
    local result: Bytes;

    %{ memory[ap - 1] = oracle(ids) %}

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

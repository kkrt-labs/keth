from starkware.cairo.common.bitwise import BitwiseBuiltin

from ethereum_types.bytes import Bytes, BytesStruct
from ethereum_rlp.rlp_types import Extended

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

struct OptionalInternalNode {
    value: InternalNodeEnum*,
}

struct InternalNodeEnum {
    leaf_node: LeafNode,
    extension_node: ExtensionNode,
    branch_node: BranchNode,
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

from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

from ethereum.cancun.trie import (
    InternalNode,
    LeafNode,
    LeafNodeStruct,
    BranchNode,
    BranchNodeStruct,
    ExtensionNode,
    ExtensionNodeStruct,
    Subnodes,
    InternalNodeEnum,
    SubnodesStruct,
    bytes_to_nibble_list,
)
from ethereum_rlp.rlp import Extended, ExtendedImpl
from ethereum_types.bytes import Bytes, BytesStruct
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import assert_not_zero

from cairo_core.comparison import is_zero
from cairo_core.control_flow import raise

func deserialize_to_internal_node{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    decoded: Extended
) -> InternalNode {
    alloc_locals;
    // Verify it's a sequence
    with_attr error_message("DecodingError") {
        assert cast(decoded.value.bytes.value, felt) = 0;
    }

    let items_len = decoded.value.sequence.value.len;
    let items = decoded.value.sequence.value.data;

    // A node must have either 2 items (leaf/extension) or 17 items (branch)
    with_attr error_message("DecodingError") {
        assert (items_len - 2) * (items_len - 17) = 0;
    }

    // Case 1: Branch node (17 items)
    if (items_len == 17) {
        tempvar subnodes = Subnodes(
            new SubnodesStruct(
                Extended(items[0].value),
                Extended(items[1].value),
                Extended(items[2].value),
                Extended(items[3].value),
                Extended(items[4].value),
                Extended(items[5].value),
                Extended(items[6].value),
                Extended(items[7].value),
                Extended(items[8].value),
                Extended(items[9].value),
                Extended(items[10].value),
                Extended(items[11].value),
                Extended(items[12].value),
                Extended(items[13].value),
                Extended(items[14].value),
                Extended(items[15].value),
            ),
        );
        let value_item = Extended(items[16].value);

        tempvar branch_node = BranchNode(new BranchNodeStruct(subnodes=subnodes, value=value_item));

        // Return internal node with branch node variant
        tempvar result = InternalNode(
            new InternalNodeEnum(
                leaf_node=LeafNode(cast(0, LeafNodeStruct*)),
                extension_node=ExtensionNode(cast(0, ExtensionNodeStruct*)),
                branch_node=branch_node,
            ),
        );

        return result;
    }

    // Case Leaf Node or Extension Node

    let prefix = items[0].value.bytes;
    let value = items[1];

    let nibbles = bytes_to_nibble_list(prefix);
    let first_nibble = nibbles.value.data[0];
    // If the first nibble is 1 or 3, this means the real key is odd length and we need to remove the first nibble
    if ((first_nibble - 1) * (first_nibble - 3) == 0) {
        tempvar nibbles = Bytes(new BytesStruct(nibbles.value.data + 1, nibbles.value.len - 1));
    } else {
        // Else this means the real key is even length and we need to remove the first two nibbles (the flag itself and a padded zero)
        tempvar nibbles = Bytes(new BytesStruct(nibbles.value.data + 2, nibbles.value.len - 2));
    }
    let is_leaf = is_zero((first_nibble - 2) * (first_nibble - 3));
    let nibbles = nibbles;

    if (is_leaf != 0) {
        // Invariant check: value in the case of a leaf node must be Extended:bytes
        if (cast(value.value.bytes.value, felt) == 0) {
            raise('DecodingError');
        }
        tempvar leaf_node = LeafNode(new LeafNodeStruct(rest_of_key=nibbles, value=value));

        tempvar result = InternalNode(
            new InternalNodeEnum(
                leaf_node=leaf_node,
                extension_node=ExtensionNode(cast(0, ExtensionNodeStruct*)),
                branch_node=BranchNode(cast(0, BranchNodeStruct*)),
            ),
        );
        return result;
    }

    tempvar extension_node = ExtensionNode(
        new ExtensionNodeStruct(key_segment=nibbles, subnode=value)
    );

    tempvar result = InternalNode(
        new InternalNodeEnum(
            leaf_node=LeafNode(cast(0, LeafNodeStruct*)),
            extension_node=extension_node,
            branch_node=BranchNode(cast(0, BranchNodeStruct*)),
        ),
    );
    return result;
}

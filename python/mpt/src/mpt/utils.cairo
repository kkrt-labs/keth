from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

from ethereum.prague.trie import (
    InternalNode,
    OptionalInternalNode,
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
from ethereum_rlp.rlp import Extended, ExtendedEnum, ExtendedImpl, decode, encode
from ethereum_types.bytes import Bytes, BytesStruct
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math_cmp import is_le_felt
from cairo_core.comparison import is_zero, is_not_zero
from cairo_core.control_flow import raise, raise_ValueError

from mpt.types import (
    AccountDiff,
    StorageDiff,
    AccountDiffStruct,
    AddressAccountDiffEntry,
    StorageDiffStruct,
)

func decode_to_internal_node{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    node: Bytes
) -> InternalNode {
    alloc_locals;
    let decoded = decode(node);
    let extended = ExtendedImpl.from_simple(decoded);
    return deserialize_to_internal_node(extended);
}

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

// @notice Checks if a branch node is valid.
// A branch node is valid if it has at least two non-null subnodes.
// @dev Raises an error if the branch node is invalid.
// @param node The branch node to check.
func check_branch_node(node: BranchNode) {
    alloc_locals;

    // Values in Ethereum MPTs are always empty bytes
    let bytes_variant = node.value.value.value.bytes.value;
    if (cast(bytes_variant, felt) == 0) {
        raise_ValueError('NonEmptyBytesValue');
    }
    if (bytes_variant.len != 0) {
        raise_ValueError('NonEmptyBytesValue');
    }

    local first_non_null_index;
    local second_non_null_index;
    let subnodes_ptr = cast(node.value.subnodes.value, felt*);

    %{ find_two_non_null_subnodes %}

    if (first_non_null_index == second_non_null_index) {
        raise_ValueError('LTTwoNonNullSubnodes');
    }

    // Check that the first subnode is not None and not empty
    tempvar x = Extended(cast(subnodes_ptr[first_non_null_index], ExtendedEnum*));

    if (cast(x.value, felt) == 0) {
        raise_ValueError('LTTwoNonNullSubnodes');
    }
    // Case 1: subnode is a digest
    if (cast(x.value.bytes.value, felt) != 0) {
        if (x.value.bytes.value.len == 0) {
            raise_ValueError('LTTwoNonNullSubnodes');
        }
    }
    // Case 2: subnode is an embedded node
    if (cast(x.value.sequence.value, felt) != 0) {
        if (x.value.sequence.value.len == 0) {
            raise_ValueError('LTTwoNonNullSubnodes');
        }
        // Embedded nodes must have RLP encoding size < 32
        let encoded = encode(x);
        if (encoded.value.len >= 32) {
            raise_ValueError('EmbeddedNodeTooLarge');
        }
    }

    // Check that the second subnode is not None and not empty
    tempvar y = Extended(cast(subnodes_ptr[second_non_null_index], ExtendedEnum*));

    if (cast(y.value, felt) == 0) {
        raise_ValueError('LTTwoNonNullSubnodes');
    }
    if (cast(y.value.bytes.value, felt) != 0) {
        if (y.value.bytes.value.len == 0) {
            raise_ValueError('LTTwoNonNullSubnodes');
        }
    }
    if (cast(y.value.sequence.value, felt) != 0) {
        if (y.value.sequence.value.len == 0) {
            raise_ValueError('LTTwoNonNullSubnodes');
        }
        // Embedded nodes must have RLP encoding size < 32
        let encoded = encode(y);
        if (encoded.value.len >= 32) {
            raise_ValueError('EmbeddedNodeTooLarge');
        }
    }

    return ();
}

func check_leaf_node(path: Bytes, node: LeafNode) {
    alloc_locals;

    let nibbles_len = node.value.rest_of_key.value.len;
    let path_len = path.value.len;

    if (nibbles_len + path_len != 64) {
        raise_ValueError('InvalidFullPath');
    }

    let bytes_variant = node.value.value.value.bytes.value;
    if (cast(bytes_variant, felt) != 0) {
        if (bytes_variant.len == 0) {
            raise_ValueError('EmptyValue');
        }
        return ();
    }

    let sequence_variant = node.value.value.value.sequence.value;
    if (cast(sequence_variant, felt) != 0) {
        if (sequence_variant.len == 0) {
            raise_ValueError('EmptyValue');
        }
        return ();
    }

    with_attr error_message("ValueError: UnsupportedVariant") {
        jmp raise.raise_label;
    }
}

// @notice Checks if an extension node is valid.
// @param node The extension node to check.
// @param parent_node The parent of the extension node
// @dev Raises an error if:
// - The key segment is empty
// - The subnode is not a valid node
// - The parent is an extension node
func check_extension_node(node: ExtensionNode, parent_node: OptionalInternalNode) {
    alloc_locals;

    if (cast(parent_node.value, felt) != 0) {
        if (cast(parent_node.value.extension_node.value, felt) != 0) {
            raise_ValueError('InvalidParent');
        }
    }

    let key_segment = node.value.key_segment;
    let subnode = node.value.subnode;

    if (key_segment.value.len == 0) {
        raise_ValueError('EmptyKeySegment');
    }

    let bytes_variant = subnode.value.bytes.value;
    if (cast(bytes_variant, felt) != 0) {
        if (bytes_variant.len == 0) {
            raise_ValueError('EmptySubnode');
        }
        return ();
    }

    let sequence_variant = subnode.value.sequence.value;
    if (cast(sequence_variant, felt) != 0) {
        if (sequence_variant.len == 0) {
            raise_ValueError('EmptySubnode');
        }
        // Embedded node must have RLP encoding size < 32
        let encoded = encode(subnode);
        if (encoded.value.len >= 32) {
            raise_ValueError('EmbeddedNodeTooLarge');
        }
        return ();
    }

    with_attr error_message("ValueError: UnsupportedVariant") {
        jmp raise.raise_label;
    }
}

// @notice Sorts an AccountDiff struct in ascending order based on the key.
// This function implies that the original AccountDiff struct does not contain any duplicate keys.
// @dev The sorted segment is returned from the hint.
// Verifications:
// - The sorted segment is in strict ascending order based on the key.
//    (for all i in [0, diffs_len - 1], sorted_diff_struct.data[i].value.key < sorted_diff_struct.data[i + 1].value.key)
// - The sorted segment is a permutation of the original segment (
//    (for all i in [0, diffs_len - 1], exists j in [0, diffs_len - 1] such that sorted_diff_struct.data[i].value.key = original_diff_struct.data[j].value.key)
//    AND len(sorted_diff_struct) = len(original_diff_struct)
// @param account_diff The AccountDiff struct to sort.
// @return The sorted AccountDiff struct.
func sort_account_diff{range_check_ptr}(account_diff: AccountDiff) -> AccountDiff {
    alloc_locals;
    let diffs_len = account_diff.value.len;
    if (diffs_len == 0) {
        // If the input diff is empty, it's already sorted
        return account_diff;
    }

    // Pointer to the original, unsorted data
    tempvar diffs_ptr = account_diff.value.data;
    // A map(sorted_index -> original_index) to store the original index corresponding to each entry in the sorted buffer
    let (buffer) = alloc();
    let (local sorted_to_original_index_map) = alloc();

    %{ sort_account_diff %}

    tempvar sorted_diff_struct = new AccountDiffStruct(
        data=cast(buffer, AddressAccountDiffEntry*), len=diffs_len
    );
    local sorted_diff_struct_ptr: AccountDiffStruct* = sorted_diff_struct;
    tempvar range_check_ptr = range_check_ptr;
    tempvar loop_counter = 0;

    loop:
    let range_check_ptr = [ap - 2];
    let loop_counter = [ap - 1];
    let original_diff_struct_ptr = cast([fp - 3], AccountDiffStruct*);

    // --- Verification Step 1: Permutation Check ---
    // Ensure that the element at the current sorted position (`loop_counter`)
    // corresponds exactly to an element from the original array, using the
    // `original_index` provided by the hint's `original_index_map`.

    with_attr error_message("ValueError: MismatchAtIndex") {
        let original_index = [sorted_to_original_index_map + loop_counter];
        tempvar original_entry: AddressAccountDiffEntry = original_diff_struct_ptr.data[
            original_index
        ];
        tempvar sorted_entry: AddressAccountDiffEntry = sorted_diff_struct_ptr.data[loop_counter];
        // Identical keys & struct pointers at this index
        assert original_entry.value.key.value = sorted_entry.value.key.value;
        assert sorted_entry.value = original_entry.value;
    }

    // `diffs_len - loop_counter - 1` is safe because diffs_len >= 1 and loop_counter starts at 0.
    let is_last_element = is_zero(original_diff_struct_ptr.len - loop_counter - 1);
    tempvar next_loop_counter = loop_counter + 1;
    jmp end if is_last_element != 0;

    // --- Verification Step 2: Ordering Check ---
    // Ensure that the sorted array is in strict ascending order based on the key.
    // This check is performed for elements from index 1 up to diffs_len - 1.
    with_attr error_message("ValueError: NotAscendingOrder") {
        let previous_key = sorted_diff_struct_ptr.data[loop_counter].value.key.value;
        let next_key = sorted_diff_struct_ptr.data[next_loop_counter].value.key.value;
        let keys_ordered = is_le_felt(previous_key, next_key);
        let keys_not_equal = is_not_zero(next_key - previous_key);
        assert keys_ordered * keys_not_equal = 1;
    }
    tempvar range_check_ptr = range_check_ptr;
    tempvar loop_counter = next_loop_counter;
    jmp loop;

    end:
    let final_loop_counter = [ap - 1];
    // --- Verification Step 3: Loop Count Check ---
    // Ensure that the loop executed exactly `diffs_len` times, confirming that
    // all elements were processed and the length of the sorted array matches the original.
    assert final_loop_counter = diffs_len;
    let sorted_account_diff = AccountDiff(sorted_diff_struct_ptr);
    return sorted_account_diff;
}

func sort_storage_diff{range_check_ptr}(storage_diff: StorageDiff) -> StorageDiff {
    // Both structs have the same layout (felt, ptr, ptr) thus we can cast one into the other
    let casted_storage_diff = AccountDiff(cast(storage_diff.value, AccountDiffStruct*));
    let diff = sort_account_diff(casted_storage_diff);
    let res = StorageDiff(cast(diff.value, StorageDiffStruct*));
    return res;
}

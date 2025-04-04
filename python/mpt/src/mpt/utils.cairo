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
from ethereum_rlp.rlp import Extended, ExtendedImpl, ExtendedEnum
from ethereum_types.bytes import Bytes, BytesStruct
from ethereum_types.numeric import bool
from ethereum.utils.bytes import Bytes__eq__
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.math_cmp import is_le_felt
from cairo_core.comparison import is_zero
from cairo_core.control_flow import raise
from ethereum.crypto.hash import Hash32__eq__

from ethereum.utils.numeric import U256__eq__
from mpt.types import (
    AccountDiff,
    StorageDiff,
    AccountDiffStruct,
    AddressAccountNodeDiffEntry,
    AddressAccountNodeDiffEntryStruct,
    AccountNode,
)

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

    local first_non_null_index;
    local second_non_null_index;
    let subnodes_ptr = cast(node.value.subnodes.value, felt*);

    %{ find_two_non_null_subnodes %}

    if (first_non_null_index == second_non_null_index) {
        raise('ValueError');
    }

    // Check that the first subnode is not None and not empty
    tempvar x = Extended(cast(subnodes_ptr[first_non_null_index], ExtendedEnum*));

    if (cast(x.value, felt) == 0) {
        raise('ValueError');
    }
    // Case 1: subnode is a digest
    if (cast(x.value.bytes.value, felt) != 0) {
        if (x.value.bytes.value.len == 0) {
            raise('ValueError');
        }
    }
    // Case 2: subnode is an embedded node
    if (cast(x.value.sequence.value, felt) != 0) {
        if (x.value.sequence.value.len == 0) {
            raise('ValueError');
        }
    }

    // Check that the second subnode is not None and not empty
    tempvar y = Extended(cast(subnodes_ptr[second_non_null_index], ExtendedEnum*));

    if (cast(y.value, felt) == 0) {
        raise('ValueError');
    }
    if (cast(y.value.bytes.value, felt) != 0) {
        if (y.value.bytes.value.len == 0) {
            raise('ValueError');
        }
    }
    if (cast(y.value.sequence.value, felt) != 0) {
        if (y.value.sequence.value.len == 0) {
            raise('ValueError');
        }
    }
    return ();
}

func sort_AccountDiff{range_check_ptr}(diff: AccountDiff) -> AccountDiff {
    alloc_locals;
    // Length of the array
    let diffs_len = diff.value.len;
    if (diffs_len == 0) {
        return diff;
    }
    // Pointer to the array of AddressAccountNodeDiffEntry
    let diffs_ptr = diff.value.data.value;
    // Buffer to store the sorted entries
    let (buffer) = alloc();
    let (sorted_indexes) = alloc();
    %{
        data = [[memory[ids.diffs_ptr.address_ + i * 3], ids.diffs_ptr.address_ + i * 3] for i in range(ids.diffs_len)]
        sorted_data = sorted(data, key=lambda x: x[0], reverse=True)
        flattened_data = [entry[1] for entry in sorted_data]
        segments.load_data(
            ids.buffer,
            flattened_data
        )

        sorted_indexes = [data.index(entry) for entry in sorted_data]
        segments.load_data(
            ids.sorted_indexes,
            [int(item) for item in sorted_indexes]
        )
    %}

    tempvar sorted_account_diffs = new AccountDiffStruct(
        data=cast(buffer, AddressAccountNodeDiffEntry*), len=diffs_len
    );
    tempvar i = 0;
    local sorted_account_diffs: AccountDiffStruct* = sorted_account_diffs;
    local sorted_indexes: felt* = sorted_indexes;
    local range_check_ptr = range_check_ptr;

    static_assert i == [ap - 1];

    loop:
    let i = [ap - 1];
    let unsorted = cast([fp - 3], AccountDiffStruct*);

    // Check that the sorted array is a permutation of the unsorted array
    // With corresponding indexes given as oracle
    with_attr error_message("KeyError") {
        let sorted_index = [sorted_indexes + i];

        let unsorted_key_at_index = unsorted.data[sorted_index].value.key.value;
        let sorted_key_at_index = sorted_account_diffs.data[i].value.key.value;

        assert unsorted_key_at_index = sorted_key_at_index;
        assert sorted_account_diffs.data[i].value = unsorted.data[sorted_index].value;
    }

    let is_end = is_zero(unsorted.len - i - 1);
    let continue_loop = 1 - is_end;

    // Check that the sorted array is ordered
    with_attr error_message("ValueError") {
        if (is_end == 0) {
            // If we are not at the end,
            // We can access offset i + 1
            let is_ordered = is_le_felt(
                sorted_account_diffs.data[i].value.key.value,
                sorted_account_diffs.data[i + 1].value.key.value,
            );
            assert is_ordered = 1;
            tempvar range_check_ptr = range_check_ptr;
        } else {
            tempvar range_check_ptr = range_check_ptr;
        }
    }

    tempvar i = i + 1;

    jmp loop if continue_loop != 0;

    // Check that the loop has been executed the correct number of times
    // Such that we know len(sorted) == len(initial_array)
    let i = [ap - 1];
    assert i = diffs_len;

    let res = AccountDiff(sorted_account_diffs);

    return res;
}

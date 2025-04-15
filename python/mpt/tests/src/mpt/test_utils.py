from typing import List, Optional, Sequence, Tuple, Union

from ethereum.cancun.trie import (
    BranchNode,
    ExtensionNode,
    InternalNode,
    LeafNode,
    bytes_to_nibble_list,
    encode_internal_node,
)
from ethereum_rlp import rlp
from ethereum_types.bytes import Bytes
from hypothesis import assume, given
from hypothesis import strategies as st

from cairo_addons.testing.errors import strict_raises
from cairo_addons.testing.hints import patch_hint
from mpt.utils import (
    check_branch_node,
    check_extension_node,
    check_leaf_node,
    nibble_list_to_bytes,
)
from tests.utils.args_gen import AddressAccountDiffEntry, StorageDiffEntry

list_address_account_node_diff_entry_strategy = st.lists(
    st.from_type(AddressAccountDiffEntry),
    min_size=0,
    max_size=10,
    unique_by=lambda x: x.key,
)


list_address_account_node_diff_entry_strategy_min_size_2 = st.lists(
    st.from_type(AddressAccountDiffEntry),
    min_size=2,
    max_size=10,
    unique_by=lambda x: x.key,
)


@st.composite
def list_address_account_node_diff_entry_strategy_with_duplicates(draw):
    """Creates a list of AddressAccountDiffEntry with duplicates"""
    data = draw(list_address_account_node_diff_entry_strategy_min_size_2)
    data[0] = data[1]
    return data


@st.composite
def branch_node_could_be_invalid_strategy(draw):
    """
    Creates a branch node that could either be valid or invalid.
    Invalid cases:
    1. Non-empty value.
    2. Less than two non-null subnodes.
    """
    test_cases = st.sampled_from(["invalid_value", "less_than_two_subnodes", "ok"])
    test_case = draw(test_cases)

    match test_case:
        case "invalid_value":
            # Value must be either non-empty bytes or not bytes
            value = draw(
                st.one_of(
                    st.binary(min_size=1, max_size=10),
                    st.integers(),
                    st.lists(st.integers()),
                )
            )
            # Subnodes can be anything >= 2 non-null for this case
            n_non_null = draw(st.integers(min_value=2, max_value=16))
            n_null = 16 - n_non_null
        case "less_than_two_subnodes":
            # Value must be empty bytes
            value = b""
            # Must have 0 or 1 non-null subnodes
            n_non_null = draw(st.integers(min_value=0, max_value=1))
            n_null = 16 - n_non_null
        case "ok":
            # Value must be empty bytes
            value = b""
            # Must have >= 2 non-null subnodes
            n_non_null = draw(st.integers(min_value=2, max_value=16))
            n_null = 16 - n_non_null
        case _:
            raise ValueError(f"Invalid strategy: {test_case}")

    # Strategy for null subnodes (empty bytes or empty list)
    null_subnode_strategy = st.one_of(st.just(b""), st.just([]))
    # Strategy for valid subnodes (any non-empty bytes)
    valid_subnode_strategy = st.from_type(LeafNode).map(encode_internal_node)

    # Generate the required number of null and non-null subnodes
    non_null_subnodes = draw(
        st.lists(valid_subnode_strategy, min_size=n_non_null, max_size=n_non_null)
    )
    null_subnodes = draw(
        st.lists(null_subnode_strategy, min_size=n_null, max_size=n_null)
    )

    # Combine and shuffle subnodes
    subnodes = draw(st.permutations(non_null_subnodes + null_subnodes))

    return BranchNode(subnodes=tuple(subnodes), value=value)


@st.composite
def leaf_node_could_be_invalid_strategy(draw):
    """Creates a leaf node associated to a path that could either be valid or invalid"""
    full_path = draw(st.binary(min_size=32, max_size=32))
    test_cases = st.sampled_from(
        ["rest_of_key_too_short", "rest_of_key_too_long", "invalid_value", "ok"]
    )
    test_case = draw(test_cases)

    match test_case:
        case "rest_of_key_too_short":
            # Create a path and rest_of_key that together are too short
            path_size = draw(st.integers(min_value=0, max_value=31))
            missing_size = draw(st.integers(min_value=1, max_value=32 - path_size))
            rest_of_key_size = 32 - path_size - missing_size
            path = bytes_to_nibble_list(full_path[:path_size])
            rest_of_key = bytes_to_nibble_list(
                full_path[path_size : path_size + rest_of_key_size]
            )
            return path, LeafNode(rest_of_key=rest_of_key, value=b"")

        case "rest_of_key_too_long":
            # Create a path and rest_of_key that together are too long
            path = bytes_to_nibble_list(full_path[:-5])
            rest_of_key = bytes_to_nibble_list(
                full_path[-5:] + b"\x01"
            )  # Add extra byte
            return path, LeafNode(rest_of_key=rest_of_key, value=b"")

        case "invalid_value":
            # Create a leaf node with invalid value (0)
            path = bytes_to_nibble_list(full_path[:16])
            rest_of_key = bytes_to_nibble_list(full_path[16:])
            # Assuming we're only working with `bytes` or `Sequence[rlp.Extended]` types.
            value = draw(st.from_type(Union[Sequence[rlp.Extended], bytes]))
            assume(len(value) == 0)
            return path, LeafNode(rest_of_key=rest_of_key, value=value)

        case "ok":
            # Create a valid leaf node
            path = bytes_to_nibble_list(full_path[:16])
            rest_of_key = bytes_to_nibble_list(full_path[16:])
            value = draw(st.from_type(Union[Sequence[rlp.Extended], bytes]))
            assume(len(value) != 0)
            return path, LeafNode(rest_of_key=rest_of_key, value=value)


@st.composite
def extension_node_could_be_invalid_strategy(draw):
    """Creates an extension node that could either be valid or invalid"""
    test_cases = st.sampled_from(["key_segment_zero", "subnode_zero", "ok"])
    test_case = draw(test_cases)

    match test_case:
        case "key_segment_zero":
            key_segment = b""
            subnode = draw(st.from_type(rlp.Extended))
            return ExtensionNode(key_segment=key_segment, subnode=subnode)

        case "subnode_zero":
            key_segment = draw(st.binary(min_size=1, max_size=32))
            subnode = draw(st.one_of(st.just(b""), st.just([])))
            return ExtensionNode(key_segment=key_segment, subnode=subnode)

        case "ok":
            key_segment = draw(st.binary(min_size=1, max_size=32))
            subnode = draw(st.from_type(Union[Sequence[rlp.Extended], bytes]))
            assume(len(subnode) != 0)
            return ExtensionNode(key_segment=key_segment, subnode=subnode)


class TestUtils:
    @given(bytes=...)
    def test_nibble_list_to_bytes(self, bytes: Bytes):
        assert nibble_list_to_bytes(bytes_to_nibble_list(bytes)) == bytes

    @given(branch_node=branch_node_could_be_invalid_strategy())
    def test_check_branch_node(self, cairo_run, branch_node: BranchNode):
        try:
            cairo_run("check_branch_node", branch_node)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                check_branch_node(branch_node)
            return

        check_branch_node(branch_node)

    @given(data=st.data())
    def test_check_branch_node_invalid_x_branch(
        self, cairo_programs, rust_programs, cairo_run, data
    ):
        node_0 = data.draw(st.one_of(st.just([]), st.just(b"")))
        node_1 = data.draw(st.one_of(st.just([]), st.just(b"")))
        branch_node = BranchNode(
            subnodes=[node_0] + [node_1] + [b""] * 14,
            value=b"",
        )
        with patch_hint(
            cairo_programs,
            rust_programs,
            "find_two_non_null_subnodes",
            """
ids.first_non_null_index = 0
ids.second_non_null_index = 1
    """,
        ):
            with strict_raises(ValueError):
                cairo_run("check_branch_node", branch_node)

    @given(data=leaf_node_could_be_invalid_strategy())
    def test_check_leaf_node(self, cairo_run, data: Tuple[Bytes, LeafNode]):
        path, leaf_node = data
        try:
            cairo_run("check_leaf_node", path, leaf_node)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                check_leaf_node(path, leaf_node)
            return

        check_leaf_node(path, leaf_node)

    @given(
        extension_node=extension_node_could_be_invalid_strategy(),
        parent=st.one_of(st.none(), st.from_type(InternalNode)),
    )
    def test_check_extension_node(
        self, cairo_run, extension_node: ExtensionNode, parent: Optional[InternalNode]
    ):
        try:
            cairo_run("check_extension_node", extension_node, parent)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                check_extension_node(extension_node, parent)
            return

    @given(data=list_address_account_node_diff_entry_strategy)
    def test_sort_account_diff(self, cairo_run, data: List[AddressAccountDiffEntry]):
        sorted_data = sorted(data, key=lambda x: int.from_bytes(x.key, "little"))
        cairo_data = cairo_run("sort_account_diff", data)
        assert cairo_data == sorted_data

    @given(data=list_address_account_node_diff_entry_strategy_min_size_2)
    def test_sort_account_diff_should_fail_if_not_ascending_order(
        self,
        cairo_programs,
        rust_programs,
        cairo_run,
        data: List[AddressAccountDiffEntry],
    ):
        with patch_hint(
            cairo_programs,
            rust_programs,
            "sort_account_diff",
            """
pointers = [memory[ids.diffs_ptr.address_ + i] for i in range(ids.diffs_len)]
sorted_pointers = sorted(pointers, key=lambda ptr: memory[ptr])

# BAD HINT: Invert the order of the last two elements
sorted_pointers[-2], sorted_pointers[-1] = sorted_pointers[-1], sorted_pointers[-2]

segments.load_data(ids.buffer, sorted_pointers)

indices = list(range(ids.diffs_len))
sorted_to_original_index_map = sorted(indices, key=lambda i: memory[pointers[i]])

# BAD HINT: Invert the order of the last two elements
sorted_to_original_index_map[-2], sorted_to_original_index_map[-1] = sorted_to_original_index_map[-1], sorted_to_original_index_map[-2]

segments.load_data(ids.sorted_to_original_index_map, sorted_to_original_index_map)
            """,
        ):
            with strict_raises(
                Exception, match="ValueError: Array is not sorted in ascending order"
            ):
                cairo_run("sort_account_diff", data)

    @given(data=list_address_account_node_diff_entry_strategy_min_size_2)
    def test_sort_account_diff_different_lists(
        self,
        cairo_programs,
        rust_programs,
        cairo_run,
        data: List[AddressAccountDiffEntry],
    ):
        with patch_hint(
            cairo_programs,
            rust_programs,
            "sort_account_diff",
            """
pointers = [memory[ids.diffs_ptr.address_ + i] for i in range(ids.diffs_len)]
sorted_pointers = sorted(pointers, key=lambda ptr: memory[ptr])

# BAD HINT: not a permutation of the input list
sorted_pointers[0] += 1

segments.load_data(ids.buffer, sorted_pointers)

indices = list(range(ids.diffs_len))
sorted_to_original_index_map = sorted(indices, key=lambda i: memory[pointers[i]])
segments.load_data(ids.sorted_to_original_index_map, sorted_to_original_index_map)
            """,
        ):
            with strict_raises(
                Exception,
                match="ValueError: Sorted element does not match original element at hint index",
            ):
                cairo_run("sort_account_diff", data)

    @given(data=list_address_account_node_diff_entry_strategy_with_duplicates())
    def test_sort_account_diff_sorted_list_with_duplicates(
        self, cairo_run, data: List[AddressAccountDiffEntry]
    ):

        with strict_raises(
            Exception, match="ValueError: Array is not sorted in ascending order"
        ):
            cairo_run("sort_account_diff", data)

    @given(data=list_address_account_node_diff_entry_strategy_min_size_2)
    def test_sort_account_diff_sorted_list_too_short(
        self,
        cairo_programs,
        rust_programs,
        cairo_run,
        data: List[AddressAccountDiffEntry],
    ):
        with patch_hint(
            cairo_programs,
            rust_programs,
            "sort_account_diff",
            """
pointers = [memory[ids.diffs_ptr.address_ + i] for i in range(ids.diffs_len)]
sorted_pointers = sorted(pointers, key=lambda ptr: memory[ptr])

# BAD HINT: list shorter than input list
sorted_pointers = sorted_pointers[:-1]

segments.load_data(ids.buffer, sorted_pointers)

indices = list(range(ids.diffs_len))
sorted_to_original_index_map = sorted(indices, key=lambda i: memory[pointers[i]])
sorted_to_original_index_map = sorted_to_original_index_map[:-1]
segments.load_data(ids.sorted_to_original_index_map, sorted_to_original_index_map)
            """,
        ):

            with strict_raises(Exception):
                cairo_run("sort_account_diff", data)

    @given(
        data=st.lists(
            st.from_type(StorageDiffEntry),
            min_size=0,
            max_size=10,
            unique_by=lambda x: x.key,
        )
    )
    def test_sort_storage_diff(self, cairo_run, data: List[StorageDiffEntry]):
        sorted_data = sorted(data, key=lambda x: x.key._number)
        cairo_data = cairo_run("sort_storage_diff", data)
        assert cairo_data == sorted_data

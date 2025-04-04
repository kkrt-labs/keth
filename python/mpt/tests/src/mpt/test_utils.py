from typing import List

from ethereum.cancun.trie import (
    BranchNode,
    LeafNode,
    bytes_to_nibble_list,
    encode_internal_node,
)
from ethereum_types.bytes import Bytes
from hypothesis import given
from hypothesis import strategies as st

from cairo_addons.testing.errors import strict_raises
from cairo_addons.testing.hints import patch_hint
from mpt.utils import check_branch_node, nibble_list_to_bytes
from tests.utils.args_gen import AddressAccountNodeDiffEntry


@st.composite
def branch_node_could_be_invalid_strategy(draw):
    """Creates a branch node that could either be valid or invalid"""
    n_leaves = draw(st.integers(min_value=0, max_value=5))

    # Create list of n_leaves LeafNodes and fill rest with empty values
    leaf_nodes = draw(
        st.lists(st.from_type(LeafNode), min_size=n_leaves, max_size=n_leaves).map(
            lambda nodes: [encode_internal_node(node) for node in nodes]
        )
    )
    empty_nodes = draw(
        st.lists(
            st.one_of(st.just(b""), st.just([])),
            min_size=16 - n_leaves,
            max_size=16 - n_leaves,
        )
    )

    return BranchNode(
        subnodes=draw(st.permutations(leaf_nodes + empty_nodes)),
        value=b"",
    )


class TestUtils:
    @given(bytes=...)
    def test_nibble_list_to_bytes(self, bytes: Bytes):
        assert nibble_list_to_bytes(bytes_to_nibble_list(bytes)) == bytes

    @given(branch_node=branch_node_could_be_invalid_strategy())
    def test_check_branch_node(self, cairo_run, branch_node: BranchNode):
        try:
            cairo_run("check_branch_node", branch_node)
        except ValueError as cairo_error:
            with strict_raises(type(cairo_error)):
                check_branch_node(branch_node)
            return

        check_branch_node(branch_node)

    @given(data=st.data())
    def test_check_branch_node_invalid_x_branch(
        self, cairo_programs, cairo_run_py, data
    ):
        node_0 = data.draw(st.one_of(st.just([]), st.just(b"")))
        node_1 = data.draw(st.one_of(st.just([]), st.just(b"")))
        branch_node = BranchNode(
            subnodes=[node_0] + [node_1] + [b""] * 14,
            value=b"",
        )
        with patch_hint(
            cairo_programs,
            "find_two_non_null_subnodes",
            """
ids.first_non_null_index = 0
ids.second_non_null_index = 1
    """,
        ):
            with strict_raises(ValueError):
                cairo_run_py("check_branch_node", branch_node)

    @given(data=...)
    def test_sort_account_diff(
        self, cairo_run, data: List[AddressAccountNodeDiffEntry]
    ):
        sorted_data = sorted(
            data, key=lambda x: int.from_bytes(x.key, "little"), reverse=True
        )
        cairo_data = cairo_run("sort_AccountDiff", data)
        assert cairo_data == sorted_data

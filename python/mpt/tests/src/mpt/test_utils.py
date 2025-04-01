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
from mpt.utils import check_branch_node, nibble_list_to_bytes


def invalid_branch_node_strategy():
    return st.builds(
        BranchNode,
        subnodes=st.lists(
            st.one_of(
                st.integers(min_value=0, max_value=2**256 - 1).map(
                    lambda x: x.to_bytes(32, "little")
                ),
                st.from_type(LeafNode).map(lambda x: encode_internal_node(x)),
            ),
            min_size=16,
            max_size=16,
        ).map(lambda nodes: tuple([b""] * 15 + [nodes[0]])),
        value=st.just(b""),
    )


class TestUtils:
    @given(bytes=...)
    def test_nibble_list_to_bytes(self, bytes: Bytes):
        assert nibble_list_to_bytes(bytes_to_nibble_list(bytes)) == bytes

    @given(branch_node=...)
    def test_check_branch_node(self, cairo_run, branch_node: BranchNode):
        try:
            cairo_run("check_branch_node", branch_node)
        except ValueError as cairo_error:
            with strict_raises(type(cairo_error)):
                check_branch_node(branch_node)
            return

        check_branch_node(branch_node)

    @given(invalid_branch_node=invalid_branch_node_strategy())
    def test_check_branch_node_invalid(
        self, cairo_run, invalid_branch_node: BranchNode
    ):
        try:
            cairo_run("check_branch_node", invalid_branch_node)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                check_branch_node(invalid_branch_node)
            return

        raise Exception("Did not fail")

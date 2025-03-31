from ethereum.cancun.trie import BranchNode, bytes_to_nibble_list
from ethereum_types.bytes import Bytes
from hypothesis import given

from cairo_addons.testing.errors import strict_raises
from mpt.utils import check_branch_node, nibble_list_to_bytes


class TestUtils:
    @given(bytes=...)
    def test_nibble_list_to_bytes(self, bytes: Bytes):
        assert nibble_list_to_bytes(bytes_to_nibble_list(bytes)) == bytes

    @given(branch_node=...)
    def test_check_branch_node(self, cairo_run_py, branch_node: BranchNode):
        try:
            cairo_run_py("check_branch_node", branch_node)
        except ValueError as cairo_error:
            with strict_raises(type(cairo_error)):
                check_branch_node(branch_node)
            return

        check_branch_node(branch_node)

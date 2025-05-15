from ethereum.prague.trie import (
    ExtensionNode,
    LeafNode,
    bytes_to_nibble_list,
    encode_internal_node,
)
from keth_types.types import EMPTY_TRIE_HASH

from mpt.trie_builder import TrieTestBuilder, rlp_encode_internal_node


class TestTrieBuilder:
    def test_empty_trie(self):
        builder = TrieTestBuilder()
        root_hash = builder.root()

        assert root_hash == EMPTY_TRIE_HASH

    def test_single_leaf(self):

        # Create a leaf node
        key = bytes_to_nibble_list(b"test_key")
        value = b"test_value"
        trie = TrieTestBuilder().leaf(key, value).build()
        assert isinstance(trie, LeafNode)
        assert trie.value == value and trie.rest_of_key == key

    def test_extension_with_leaf(self):
        builder = TrieTestBuilder()

        # Create an extension node pointing to a leaf
        ext = builder.extension(bytes_to_nibble_list(b"ext_segment"))
        ext.with_leaf(bytes_to_nibble_list(b"leaf_key"), b"leaf_value")
        extension_node = builder.build()

        # The extension node should be in the node store
        assert builder.root_node == extension_node
        assert builder.root() == encode_internal_node(extension_node)
        assert builder.node_store[builder.root()] == rlp_encode_internal_node(
            extension_node
        )

    def test_branch_with_multiple_children(self):
        builder = TrieTestBuilder()

        # Create a branch node with multiple children
        branch = builder.branch()
        branch.with_leaf(
            0,
            bytes_to_nibble_list(b"some_long_key_equal_to_32_bytes_"),
            b"some_value_rlp_length_greater_than_32_bytes",
        )
        branch.with_leaf(15, bytes_to_nibble_list(b"a"), b"b")
        branch.with_value(b"branch_value")
        branch_node = builder.build()

        # The branch node should be in the node store
        assert builder.root_node == branch_node
        assert builder.root() == encode_internal_node(branch_node)
        assert builder.node_store[builder.root()] == rlp_encode_internal_node(
            branch_node
        )
        assert branch_node.value == b"branch_value"

        ## We check that the first subnode is not embedded
        assert branch_node.subnodes[0] == encode_internal_node(
            LeafNode(
                bytes_to_nibble_list(b"some_long_key_equal_to_32_bytes_"),
                b"some_value_rlp_length_greater_than_32_bytes",
            )
        )
        assert (
            isinstance(branch_node.subnodes[0], bytes)
            and len(branch_node.subnodes[0]) == 32
        )

        ## We check that the last subnode is embedded
        assert branch_node.subnodes[15] == encode_internal_node(
            LeafNode(bytes_to_nibble_list(b"a"), b"b")
        )
        assert (
            isinstance(branch_node.subnodes[15], tuple)
            and len(branch_node.subnodes[15]) == 2
        )

    def test_complex_trie_structure(self):
        builder = TrieTestBuilder()

        # Create a complex trie with nested structure
        branch = builder.branch()

        # Add a leaf at index 0
        branch.with_leaf(0, bytes_to_nibble_list(b"key1"), b"value1")

        # Add an extension node at index 1 that points to a leaf
        ext1 = branch.with_extension(1, bytes_to_nibble_list(b"ext_key1"))
        ext1.with_leaf(bytes_to_nibble_list(b"leaf_key2"), b"value2")

        # Add an extension node at index 2 that points to another extension
        ext2 = branch.with_extension(2, bytes_to_nibble_list(b"ext_key2"))
        ext3 = ext2.with_extension(bytes_to_nibble_list(b"ext_key3"))
        ext3.with_leaf(bytes_to_nibble_list(b"leaf_key3"), b"value3")

        # Add a branch node at index 3
        sub_branch = branch.with_branch(3)
        sub_branch.with_leaf(
            5, bytes_to_nibble_list(b"subbranch_key"), b"subbranch_value"
        )
        sub_branch.with_value(b"branch_value")

        # Add a value to the root branch
        branch.with_value(b"root_value")

        # Build the trie
        branch_node = builder.build()

        assert builder.root() == encode_internal_node(branch_node)
        assert builder.node_store[builder.root()] == rlp_encode_internal_node(
            branch_node
        )
        assert branch_node.value == b"root_value"
        expected_subnode = ExtensionNode(
            bytes_to_nibble_list(b"ext_key2"),
            encode_internal_node(
                ExtensionNode(
                    bytes_to_nibble_list(b"ext_key3"),
                    encode_internal_node(
                        LeafNode(bytes_to_nibble_list(b"leaf_key3"), b"value3")
                    ),
                )
            ),
        )
        assert branch_node.subnodes[2] == encode_internal_node(expected_subnode)
        assert builder.node_store[branch_node.subnodes[2]] == rlp_encode_internal_node(
            expected_subnode
        )

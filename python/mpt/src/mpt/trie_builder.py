from dataclasses import dataclass
from typing import List, Mapping, Optional, Union

import ethereum_rlp as rlp
from ethereum.crypto.hash import Hash32, keccak256
from ethereum.prague.fork_types import Address
from ethereum.prague.trie import (
    BranchNode,
    ExtensionNode,
    InternalNode,
    LeafNode,
    encode_internal_node,
    nibble_list_to_compact,
)
from ethereum_types.bytes import Bytes, Bytes32

from keth_types.types import EMPTY_TRIE_HASH
from mpt.ethereum_tries import EthereumTries

NodeBuilder = Union["LeafNodeBuilder", "ExtensionNodeBuilder", "BranchNodeBuilder"]


@dataclass
class TrieTestBuilder:
    """Builder for creating test Merkle Patricia Tries with explicit structure."""

    node_store: Mapping[Hash32, Bytes]
    root_node: Optional[InternalNode]

    def __init__(self):
        self.root_node = None
        self.node_store = {}
        self._child_builder: Optional[NodeBuilder] = None

    def leaf(self, key: Bytes, value: Bytes) -> "LeafNodeBuilder":
        """Create a leaf node with the given key and value."""
        leaf_builder = LeafNodeBuilder(self, key, value)
        self._child_builder = leaf_builder
        return leaf_builder

    def extension(self, key_segment: Bytes) -> "ExtensionNodeBuilder":
        """Create an extension node with the given key segment."""
        ext_builder = ExtensionNodeBuilder(self, key_segment)
        self._child_builder = ext_builder
        return ext_builder

    def branch(self) -> "BranchNodeBuilder":
        """Create a branch node."""
        branch_builder = BranchNodeBuilder(self)
        self._child_builder = branch_builder
        return branch_builder

    def build(self) -> InternalNode:
        """Build the trie."""
        if self._child_builder is not None:
            root_node = self._child_builder.build()
        encoded_node = rlp_encode_internal_node(root_node)
        self.node_store[keccak256(encoded_node)] = encoded_node
        return self.root_node

    def root(self) -> Hash32:
        """Compute and return the root hash of the trie."""
        if self.root_node is None:
            return EMPTY_TRIE_HASH

        return keccak256(rlp_encode_internal_node(self.root_node))

    def to_ethereum_tries(
        self,
        addresses: Optional[List[Address]] = None,
        storage_keys: Optional[List[Bytes32]] = None,
    ) -> EthereumTries:
        """Convert the trie to an Ethereum Trie."""
        address_mapping = (
            {keccak256(address): address for address in addresses} if addresses else {}
        )
        storage_key_mapping = (
            {keccak256(storage_key): storage_key for storage_key in storage_keys}
            if storage_keys
            else {}
        )
        return EthereumTries(
            self.node_store, {}, address_mapping, storage_key_mapping, self.root()
        )


class LeafNodeBuilder:
    def __init__(self, builder: TrieTestBuilder, key: Bytes, value: Bytes):
        self.builder = builder
        self.key = key
        self.value = value
        self._parent_builder: Optional[NodeBuilder] = None

    def build(self) -> InternalNode:
        """Build the leaf node."""
        node = LeafNode(self.key, self.value)
        self.builder.root_node = node
        # Store the node in the node store if it's not an embedded node
        encoded_node = rlp_encode_internal_node(node)
        if len(encoded_node) >= 32:
            self.builder.node_store[keccak256(encoded_node)] = encoded_node
        return node


class ExtensionNodeBuilder:
    def __init__(self, builder: TrieTestBuilder, key_segment: Bytes):
        self.builder = builder
        self.key_segment = key_segment
        self.subnode: Optional[InternalNode] = None
        self._child_builder: Optional[NodeBuilder] = None

    def with_leaf(self, key: Bytes, value: Bytes) -> "LeafNodeBuilder":
        """Add a leaf node as the subnode."""
        leaf_builder = LeafNodeBuilder(self.builder, key, value)
        self._child_builder = leaf_builder
        return leaf_builder

    def with_extension(self, key_segment: Bytes) -> "ExtensionNodeBuilder":
        """Add an extension node as the subnode."""
        ext_builder = ExtensionNodeBuilder(self.builder, key_segment)
        self._child_builder = ext_builder
        return ext_builder

    def with_branch(self) -> "BranchNodeBuilder":
        """Add a branch node as the subnode and return it for further building."""
        branch_builder = BranchNodeBuilder(self.builder)
        self._child_builder = branch_builder
        return branch_builder

    def build(self) -> InternalNode:
        """Build the extension node."""
        if self._child_builder is not None:
            subnode = self._child_builder.build()
            encoded_subnode = encode_internal_node(subnode)
        else:
            encoded_subnode = b""
        node = ExtensionNode(self.key_segment, encoded_subnode)
        self.builder.root_node = node
        # Store the node in the node store if it's not an embedded node
        encoded_node = rlp_encode_internal_node(node)
        if len(encoded_node) >= 32:
            self.builder.node_store[keccak256(encoded_node)] = encoded_node
        return node


class BranchNodeBuilder:
    def __init__(self, builder: TrieTestBuilder):
        self.builder = builder
        self.value: Bytes = b""
        self._child_builders: List[Optional[NodeBuilder]] = [None] * 16

    def with_value(self, value: Bytes) -> "BranchNodeBuilder":
        """Set the value for this branch node."""
        self.value = value
        return self

    def with_child(
        self,
        index: int,
        node_builder: Union[
            "LeafNodeBuilder", "ExtensionNodeBuilder", "BranchNodeBuilder"
        ],
    ) -> "NodeBuilder":
        """Add a child node at the specified index."""
        if not 0 <= index < 16:
            raise ValueError(f"Branch index must be 0-15, got {index}")
        self._child_builders[index] = node_builder
        return node_builder

    def with_leaf(self, index: int, key: Bytes, value: Bytes) -> "LeafNodeBuilder":
        """Add a leaf node at the specified index."""
        leaf_builder = LeafNodeBuilder(self.builder, key, value)
        return self.with_child(index, leaf_builder)

    def with_extension(self, index: int, key_segment: Bytes) -> "ExtensionNodeBuilder":
        """Add an extension node at the specified index and return it for further building."""
        ext_builder = ExtensionNodeBuilder(self.builder, key_segment)
        return self.with_child(index, ext_builder)

    def with_branch(self, index: int) -> "BranchNodeBuilder":
        """Add a branch node at the specified index and return it for further building."""
        branch_builder = BranchNodeBuilder(self.builder)
        return self.with_child(index, branch_builder)

    def build(self) -> InternalNode:
        """Build the branch node."""
        encoded_subnodes = tuple(
            (
                encode_internal_node(self._child_builders[i].build())
                if self._child_builders[i] is not None
                else b""
            )
            for i in range(16)
        )
        node = BranchNode(encoded_subnodes, self.value)
        self.builder.root_node = node
        # Store the node in the node store if it's not an embedded node
        encoded_node = rlp_encode_internal_node(node)
        if len(encoded_node) >= 32:
            self.builder.node_store[keccak256(encoded_node)] = encoded_node
        return node


def rlp_encode_internal_node(node: Optional[InternalNode]) -> rlp.Extended:
    """
    Modified util from `ethereum.prague.trie.encode_internal_node` to return RLP encoded
    node.

    This function also accepts `None`, representing the absence of a node,
    which is encoded to `b""`.

    Parameters
    ----------
    node : Optional[InternalNode]
        The node to encode.

    Returns
    -------
    encoded : `rlp.Extended`
        The node encoded as RLP.
    """
    unencoded: rlp.Extended
    if node is None:
        unencoded = b""
    match node:
        case LeafNode():
            unencoded = (
                nibble_list_to_compact(node.rest_of_key, True),
                node.value,
            )
        case ExtensionNode():
            unencoded = (
                nibble_list_to_compact(node.key_segment, False),
                node.subnode,
            )
        case BranchNode():
            unencoded = list(node.subnodes) + [node.value]
        case _:
            raise AssertionError(f"Invalid internal node type {type(node)}!")

    return rlp.encode(unencoded)

from pathlib import Path

import pytest
from ethereum.cancun.trie import BranchNode, ExtensionNode, LeafNode
from ethereum_types.bytes import Bytes

from mpt.utils import decode_node


@pytest.mark.parametrize("path", [Path("python/mpt/tests/data/22079718.json")])
class TestUtils:
    def test_decode_node(self, zkpi):
        nodes = zkpi["witness"]["state"]
        for node in nodes:
            decoded = decode_node(Bytes.fromhex(node[2:]))
            # If decoded is neither ExtensionNode nor BranchNode nor LeafNode, then fail the test
            if not isinstance(decoded, (ExtensionNode, BranchNode, LeafNode)):
                raise ValueError(
                    f"Decoded node is not an ExtensionNode, BranchNode, or LeafNode: {decoded}"
                )

            # If decoded is an ExtensionNode, then check if there is an embedded node
            if isinstance(decoded, ExtensionNode):
                if len(decoded.subnode) != 32:
                    embedded = decode_node(decoded.subnode)
                    if not isinstance(embedded, (ExtensionNode, BranchNode, LeafNode)):
                        raise ValueError(
                            f"Embedded node is not an ExtensionNode, BranchNode, or LeafNode: {embedded}"
                        )
            # if there is a subnode where subnode.len != 32, then print it
            if isinstance(decoded, BranchNode):
                # find the subnode where len(subnode) != 32
                for subnode in decoded.subnodes:
                    if subnode and len(subnode) != 32:
                        embedded = decode_node(subnode)
                        if not isinstance(
                            embedded, (ExtensionNode, BranchNode, LeafNode)
                        ):
                            raise ValueError(
                                f"Embedded node is not an ExtensionNode, BranchNode, or LeafNode: {embedded}"
                            )

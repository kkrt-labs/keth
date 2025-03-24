from pathlib import Path

import pytest
from ethereum.cancun.trie import BranchNode, ExtensionNode
from ethereum_types.bytes import Bytes

from mpt.utils import decode_node


@pytest.mark.parametrize("path", [Path("python/mpt/tests/data/22079718.json")])
class TestUtils:
    def test_decode_embedded_node(self, zkpi):
        """
        ⚠️ TODO: this test SHOULD fail because embedded nodes are not RLP-encoded ⚠️
        """
        found_embedded_nodes = False
        nodes = zkpi["witness"]["state"]
        for node in nodes:
            decoded = decode_node(Bytes.fromhex(node[2:]))
            if isinstance(decoded, BranchNode):
                # find the subnode where len(subnode) != 32
                for subnode in decoded.subnodes:
                    if subnode and len(subnode) != 32:
                        found_embedded_nodes = True
                        decode_node(subnode)

            if isinstance(decoded, ExtensionNode) and len(decoded.subnode) != 32:
                found_embedded_nodes = True
                decode_node(decoded.subnode)

        # This test will fail when test data has embedded nodes
        assert not found_embedded_nodes

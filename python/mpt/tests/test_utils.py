from pathlib import Path

import pytest
from ethereum.cancun.trie import BranchNode
from ethereum_types.bytes import Bytes

from mpt.utils import decode_node


@pytest.mark.parametrize("path", [Path("python/mpt/tests/data/22079718.json")])
class TestUtils:
    def test_decode_embedded_node(self, zkpi):
        """
        Test that the `decode_node` function can decode embedded nodes
        And that embedded nodes are not decoded automatically when `decode_node` is called on the node that contains them
        """
        nodes = zkpi["witness"]["state"]
        for node in nodes:
            decoded = decode_node(Bytes.fromhex(node[2:]))
            if isinstance(decoded, BranchNode):
                # find the subnode where len(subnode) != 32
                for subnode in decoded.subnodes:
                    if subnode and len(subnode) != 32:
                        decode_node(subnode)

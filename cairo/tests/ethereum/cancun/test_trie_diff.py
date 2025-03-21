import json
from pathlib import Path

import pytest
from ethereum.crypto.hash import keccak256
from ethereum_types.bytes import Bytes

from mpt.utils import decode_node


@pytest.fixture
def zkpi(path: Path):
    with open(path, "r") as f:
        zkpi = json.load(f)
    return zkpi


@pytest.fixture
def node_store(zkpi):
    nodes = {
        keccak256(Bytes.fromhex(node[2:])): decode_node(Bytes.fromhex(node[2:]))
        for node in zkpi["witness"]["state"]
    }
    return nodes


@pytest.mark.parametrize("path", [Path("test-data/22081873.json")])
class TestTrieDiff:
    def test_node_store_get(self, cairo_run, node_store):
        # TODO: Investigate why 1 node takes 20s to run
        for key, value in list(node_store.items())[:1]:
            _, result_cairo = cairo_run("node_store_get", node_store, key)
            assert result_cairo == value

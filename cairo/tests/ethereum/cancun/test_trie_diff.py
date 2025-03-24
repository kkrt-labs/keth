import json
from collections import defaultdict
from pathlib import Path

import pytest
from ethereum.crypto.hash import keccak256
from ethereum_types.bytes import Bytes
from hypothesis import given, settings
from hypothesis import strategies as st

from mpt.utils import decode_node


@pytest.fixture(scope="session")
def zkpi(path: Path):
    with open(path, "r") as f:
        zkpi = json.load(f)
    return zkpi


@pytest.fixture(scope="session")
def node_store(zkpi):
    nodes = defaultdict(
        lambda: None,
        {
            keccak256(Bytes.fromhex(node[2:])): decode_node(Bytes.fromhex(node[2:]))
            for node in zkpi["witness"]["state"]
        },
    )
    return nodes


@pytest.mark.parametrize("path", [Path("test_data/22081873.json")], scope="session")
class TestTrieDiff:
    @given(
        key_indexes=st.lists(
            st.integers(min_value=0, max_value=2**16), min_size=10, max_size=20
        )
    )
    @settings(max_examples=1)
    def test_node_store_get(self, cairo_run, node_store, key_indexes):

        keys = [
            (
                list(node_store.keys())[key_index % len(node_store)]
                if i % 2 == 0
                else bytes.fromhex(hex(key_index)[2:].zfill(64))
            )
            for i, key_index in enumerate(key_indexes)
        ]
        values = [node_store.get(key) for key in keys]
        values_cairo = cairo_run("test_node_store_get", node_store, keys, len(keys))
        assert values_cairo == values

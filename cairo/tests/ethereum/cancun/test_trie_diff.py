import json
from collections import defaultdict
from pathlib import Path

import pytest
from ethereum.crypto.hash import keccak256
from ethereum_types.bytes import Bytes
from hypothesis import given
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
    @given(st.data())
    def test_node_store_get(self, cairo_run, node_store, data):
        # take 20 keys from the node_store
        small_store = defaultdict(
            lambda: None, {k: v for k, v in list(node_store.items())[:6]}
        )
        existing_keys = list(small_store.keys())
        # take sample_size keys from small_store
        sample_size = data.draw(
            st.integers(min_value=5, max_value=min(10, len(small_store)))
        )
        keys = data.draw(
            st.lists(
                st.sampled_from(existing_keys),
                min_size=sample_size,
                max_size=sample_size,
                unique=True,
            )
        )
        # add a non-existing key which should return None
        keys.append(keccak256("non_existing".encode()))

        for key in keys:
            _, result = cairo_run("node_store_get", small_store, key)
            assert result == small_store.get(key)

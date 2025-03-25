import json
from pathlib import Path

import pytest
from ethereum.crypto.hash import keccak256
from ethereum_types.bytes import Bytes

from mpt.utils import decode_node


@pytest.fixture(scope="session")
def zkpi(data_path: Path):
    with open(data_path, "r") as f:
        zkpi = json.load(f)
    return zkpi


@pytest.fixture
def branch_in_extension_data():
    """
    Fixture that creates test data for branch node embedded in extension node.
    Based on the Golang test case from <https://github.com/kkrt-labs/go-ethereum/pull/1/files>

    The test data represents a state transition with the following key-value changes of the following MPT:

    Pre-state:
    - 0x0000000000000000000000000000000000000000000000000000000000ebaba -> 0xa
    - 0x0000000000000000000000000000000000000000000000000000000000ebebe -> 0xe

    Post-state:
    - 0x0000000000000000000000000000000000000000000000000000000000ebaba -> 0xa (unchanged)
    - 0x0000000000000000000000000000000000000000000000000000000000ebebe -> 0xf (modified)
    """

    # Nodes from the Golang test case
    nodes = [
        "0xf83a9f100000000000000000000000000000000000000000000000000000000000ebd980808080808080808080c48220ba0a808080c48220be0e8080",
        "0xf83a9f100000000000000000000000000000000000000000000000000000000000ebd980808080808080808080c48220ba0a808080c48220be0f8080",
    ]

    # Create a dict similar to the zkpi structure
    test_data = {
        "nodes": {
            keccak256(Bytes.fromhex(node[2:])): decode_node(Bytes.fromhex(node[2:]))
            for node in nodes
        },
    }

    return test_data

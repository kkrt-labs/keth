import json
from pathlib import Path

from mpt.trie_diff import StateDiff
import pytest
from ethereum.cancun.fork_types import Address
from ethereum.crypto.hash import Hash32, keccak256
from ethereum_types.bytes import Bytes, Bytes32

from mpt import EthereumTries
from mpt.utils import decode_node


@pytest.fixture
def zkpi(path: Path):
    with open(path, "r") as f:
        data = json.load(f)
    return data


@pytest.fixture
def ethereum_tries(zkpi):
    return EthereumTries.from_data(zkpi)


@pytest.mark.parametrize("path", [
    (Path("python/mpt/tests/data/22081873.json")),
])
class TestTrieDiff:
    def test_trie_diff(self, ethereum_tries):
        trie_diff = StateDiff.from_tries(ethereum_tries)
        assert trie_diff._main_trie == ethereum_tries.state_diff._main_trie

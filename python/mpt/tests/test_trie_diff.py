import json
from pathlib import Path

import pytest

from mpt import EthereumTries, EthereumTrieTransitionDB
from mpt.trie_diff import StateDiff


@pytest.fixture
def zkpi(path: Path):
    with open(path, "r") as f:
        data = json.load(f)
    return data


@pytest.fixture
def ethereum_tries(zkpi):
    return EthereumTries.from_data(zkpi)


@pytest.fixture
def ethereum_trie_transition_db(zkpi):
    return EthereumTrieTransitionDB.from_data(zkpi)


@pytest.mark.parametrize(
    "path",
    [
        (Path("python/mpt/tests/data/22081873.json")),
    ],
)
class TestTrieDiff:
    def test_trie_diff(self, zkpi, ethereum_trie_transition_db):
        state_diff = StateDiff.from_data(zkpi)
        trie_diff = StateDiff.from_tries(ethereum_trie_transition_db)
        assert trie_diff._main_trie == state_diff._main_trie

from pathlib import Path

import pytest

from mpt import EthereumTrieTransitionDB
from mpt.trie_diff import StateDiff


@pytest.fixture
def ethereum_trie_transition_db(path):
    return EthereumTrieTransitionDB.from_json(path)


@pytest.mark.parametrize(
    "path",
    [
        (Path("test-data/22081873.json")),
    ],
)
class TestTrieDiff:
    def test_trie_diff(self, path, ethereum_trie_transition_db):
        state_diff = StateDiff.from_json(path)
        trie_diff = StateDiff.from_tries(ethereum_trie_transition_db)
        assert trie_diff._main_trie == state_diff._main_trie
        assert trie_diff._storage_tries == state_diff._storage_tries

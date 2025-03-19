import json
from pathlib import Path

import pytest

from mpt import EthereumTries


@pytest.fixture
def zkpi(path: Path):
    with open(path, "r") as f:
        data = json.load(f)
    return data


@pytest.mark.parametrize("path", [Path("python/mpt/tests/data/22079718.json")])
class TestEthereumTries:
    def test_from_json(self, zkpi):
        ethereum_tries = EthereumTries.from_data(zkpi)
        assert ethereum_tries is not None

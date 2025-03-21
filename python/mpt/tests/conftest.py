import json
from pathlib import Path

import pytest


@pytest.fixture
def zkpi(path: Path):
    with open(path, "r") as f:
        zkpi = json.load(f)
    return zkpi

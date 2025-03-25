import json
from pathlib import Path

import pytest


@pytest.fixture(scope="session")
def zkpi(data_path: Path):
    with open(data_path, "r") as f:
        zkpi = json.load(f)
    return zkpi

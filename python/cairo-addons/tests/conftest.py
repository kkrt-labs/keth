import json
from pathlib import Path

import pytest
from starkware.cairo.lang.compiler.program import Program


@pytest.fixture(scope="module")
def program_path():
    return Path(__file__).parent / "os.json"


@pytest.fixture(scope="module")
def program(program_path):
    return Program.load(data=json.loads(program_path.read_text()))


@pytest.fixture
def program_bytes(program):
    return json.dumps(program.Schema().dump(program)).encode()

import json
from pathlib import Path

import pytest
from cairo_addons.vm import Program as RustProgram
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


class TestProgram:
    def test_should_load_program(self, program_bytes):
        RustProgram.from_bytes(program_bytes)

    def test_should_raise_entrypoint_not_found(self, program_bytes):
        with pytest.raises(RuntimeError, match="Entrypoint no_name not found"):
            RustProgram.from_bytes(program_bytes, entrypoint="no_name")

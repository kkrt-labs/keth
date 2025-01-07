import pytest
from cairo_addons.vm import Program as RustProgram


class TestProgram:
    def test_should_load_program(self, program_bytes):
        RustProgram.from_bytes(program_bytes)

    def test_should_raise_entrypoint_not_found(self, program_bytes):
        with pytest.raises(RuntimeError, match="Entrypoint no_name not found"):
            RustProgram.from_bytes(program_bytes, entrypoint="no_name")

    def test_set_builtins(self, program_bytes):
        program = RustProgram.from_bytes(program_bytes)
        builtins = program.builtins
        program.builtins = builtins[:-1]
        assert program.builtins == builtins[:-1]

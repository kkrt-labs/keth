import pytest
from cairo_addons.vm import CairoRunner, Program


@pytest.fixture
def program(program_bytes):
    return Program.from_bytes(program_bytes)


class TestRunner:
    def test_runner_creation(self, program):
        CairoRunner(program)

    def test_initialize_segments(self, program):
        runner = CairoRunner(program)
        runner.initialize_segments()
        assert runner.program_base is not None
        assert runner.program_base.segment_index == 0
        assert runner.program_base.offset == 0

    def test_initialize_builtins(self, program):
        runner = CairoRunner(program, layout="all_cairo")
        runner.initialize_builtins(False)

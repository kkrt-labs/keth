from cairo_addons.vm import CairoRunner, Program


class TestRunner:
    def test_runner_creation(self, program_bytes):
        program = Program.from_bytes(program_bytes)
        CairoRunner(program)

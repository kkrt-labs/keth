from cairo_addons.vm import CairoRunner


class TestRunner:
    def test_runner_creation(self, rust_program):
        CairoRunner(rust_program)

    def test_initialize_segments(self, rust_program):
        runner = CairoRunner(rust_program)
        runner.initialize_segments()
        assert runner.program_base is not None
        assert runner.program_base.segment_index == 0
        assert runner.program_base.offset == 0

    def test_initialize_builtins(self, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        runner.initialize_builtins(False)

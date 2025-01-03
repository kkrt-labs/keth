from cairo_addons.vm import CairoRunner, Relocatable


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

    def test_initialize_stack(self, sw_program, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        runner.initialize_builtins(allow_missing_builtins=False)
        runner.initialize_segments()
        stack = runner.initialize_stack(sw_program.builtins)
        assert len(stack) == len(sw_program.builtins)
        assert all(isinstance(item, Relocatable) for item in stack)
        assert len(set(item.segment_index for item in stack)) == len(
            sw_program.builtins
        )
        assert all(item.offset == 0 for item in stack)

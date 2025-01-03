from cairo_addons.vm import CairoRunner, Relocatable


class TestRunner:
    def test_runner_creation(self, rust_program):
        CairoRunner(rust_program)

    def test_initialize_builtins(self, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        runner.initialize_builtins(allow_missing_builtins=False)

    def test_initialize_segments(self, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        runner.initialize_builtins(allow_missing_builtins=False)
        runner.initialize_segments()
        assert runner.program_base is not None
        assert runner.program_base.segment_index == 0
        assert runner.program_base.offset == 0

    def test_execution_base(self, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        runner.initialize_builtins(allow_missing_builtins=False)
        runner.initialize_segments()
        assert (
            runner.execution_base.segment_index == runner.program_base.segment_index + 1
        )
        assert runner.execution_base.offset == 0

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

    def test_initialize_function_entrypoint(self, sw_program, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        runner.initialize_builtins(allow_missing_builtins=False)
        runner.initialize_segments()
        stack = runner.initialize_stack(sw_program.builtins)
        return_fp = runner.execution_base + 2
        end = runner.initialize_function_entrypoint(
            sw_program.get_label("os"), stack, return_fp
        )
        assert end.segment_index == len(stack) + 2
        assert end.offset == 0

    def test_initialize_zero_segment(self, sw_program, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        runner.initialize_builtins(allow_missing_builtins=False)
        runner.initialize_segments()
        stack = runner.initialize_stack(sw_program.builtins)
        return_fp = runner.execution_base + 2
        runner.initialize_function_entrypoint(
            sw_program.get_label("os"), stack, return_fp
        )
        runner.initialize_zero_segment()

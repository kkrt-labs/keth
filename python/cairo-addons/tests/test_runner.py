from cairo_addons.vm import CairoRunner


class TestRunner:
    def test_runner_creation(self, rust_program):
        CairoRunner(rust_program)

    def test_initialize_segments(self, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        runner.initialize_segments()
        assert runner.program_base.segment_index == 0
        assert runner.execution_base.segment_index == 1

    def test_initialize(self, sw_program, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        runner.initialize_segments()

    def test_program_base(self, sw_program, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        runner.initialize_segments()
        runner.program_base

    def test_execution_base(self, sw_program, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        runner.initialize_segments()
        runner.execution_base

    def test_ap(self, sw_program, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        runner.initialize_segments()
        runner.ap

    def test_fp(self, sw_program, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        runner.initialize_segments()
        runner.fp

    def test_pc(self, sw_program, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        runner.initialize_segments()
        runner.pc

    def test_get_maybe_relocatable(self, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        base = runner.segments.add()
        expected = 0xABDE1
        runner.segments.load_data(base, [expected])
        assert runner.segments.memory.get(base) == expected

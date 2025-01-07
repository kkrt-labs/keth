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
        runner.initialize_vm(stack=[], entrypoint=sw_program.get_label("os"))

    def test_program_base(self, sw_program, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        runner.initialize_segments()
        runner.initialize_vm(stack=[], entrypoint=sw_program.get_label("os"))
        runner.program_base

    def test_execution_base(self, sw_program, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        runner.initialize_segments()
        runner.initialize_vm(stack=[], entrypoint=sw_program.get_label("os"))
        runner.execution_base

    def test_ap(self, sw_program, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        runner.initialize_segments()
        runner.initialize_vm(stack=[], entrypoint=sw_program.get_label("os"))
        runner.ap

    def test_fp(self, sw_program, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        runner.initialize_segments()
        runner.initialize_vm(stack=[], entrypoint=sw_program.get_label("os"))
        runner.fp

    def test_pc(self, sw_program, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        runner.initialize_segments()
        runner.initialize_vm(stack=[], entrypoint=sw_program.get_label("os"))
        runner.pc

    def test_relocated_trace(self, sw_program, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        runner.initialize_segments()
        runner.initialize_vm(stack=[], entrypoint=sw_program.get_label("os"))
        runner.relocated_trace

    def test_get_maybe_relocatable(self, rust_program):
        runner = CairoRunner(rust_program, layout="all_cairo")
        base = runner.segments.add()
        expected = 0xABDE1
        runner.segments.load_data(base, [expected])
        assert runner.segments.get(base) == expected

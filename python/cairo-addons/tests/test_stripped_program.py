from cairo_addons.vm import StrippedProgram


class TestStrippedProgram:
    def test_should_load_program(self, sw_program):
        program = StrippedProgram(data=sw_program.data, builtins=[], main=0)
        assert program.data == sw_program.data
        assert program.builtins == []
        assert program.main == 0

    def test_should_set_builtins(self, sw_program):
        program = StrippedProgram(data=sw_program.data, builtins=[], main=0)
        program.builtins = sw_program.builtins
        assert program.builtins == sw_program.builtins

    def test_should_set_main(self, sw_program):
        program = StrippedProgram(data=sw_program.data, builtins=[], main=0)
        program.main = sw_program.get_label("os")
        assert program.main == sw_program.get_label("os")

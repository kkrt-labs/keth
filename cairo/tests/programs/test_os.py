class TestOs:

    def test_os(self, cairo_run, block, state):
        cairo_run("test_os", block=block, state=state)

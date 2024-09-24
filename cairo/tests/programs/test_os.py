class TestOs:

    def test_os(self, cairo_run):
        assert cairo_run("test_os") == list(range(1, 9))

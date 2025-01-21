class TestSecp256k1:

    class TestGetGeneratorPoint:
        def test_get_generator_point(self, cairo_run):
            cairo_run("test__get_generator_point")

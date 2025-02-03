from hypothesis import given

from tests.utils.strategies import felt


class TestComparison:
    @given(value=felt)
    def test_is_zero(self, cairo_run, value):
        assert (value == 0) == cairo_run("is_zero", value)

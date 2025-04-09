from hypothesis import given

from cairo_addons.vm import Relocatable as RustRelocatable
from tests.utils.strategies import felt


class TestComparison:
    @given(value=felt)
    def test_is_zero(self, cairo_run, value):
        assert (value == 0) == cairo_run("is_zero", value)

    def test_ptr_equal(self, cairo_run):
        lhs = RustRelocatable(1, 1)
        rhs = RustRelocatable(1, 2)
        assert not cairo_run("is_ptr_equal", lhs, rhs)

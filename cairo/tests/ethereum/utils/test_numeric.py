from hypothesis import given
from hypothesis import strategies as st
from starkware.cairo.lang.instances import PRIME

from ethereum.base_types import Uint
from ethereum.utils.numeric import ceil32
from tests.utils.strategies import felt, uint128


class TestNumeric:
    @given(a=uint128, b=uint128)
    def test_min(self, cairo_run, a, b):
        assert min(a, b) == cairo_run("min", a, b)

    @given(a=uint128, b=uint128)
    def test_max(self, cairo_run, a, b):
        assert max(a, b) == cairo_run("max", a, b)

    @given(
        value=uint128,
        div=st.integers(min_value=1, max_value=PRIME // (2**128 - 1) - 1),
    )
    def test_divmod(self, cairo_run, value, div):
        assert list(divmod(value, div)) == cairo_run("divmod", value, div)

    @given(value=felt)
    def test_is_zero(self, cairo_run, value):
        assert (value == 0) == cairo_run("is_zero", value)

    @given(value=...)
    def test_ceil32(self, cairo_run, value: Uint):
        assert ceil32(value) == cairo_run("ceil32", value)

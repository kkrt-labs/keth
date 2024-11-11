from hypothesis import given
from hypothesis import strategies as st
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

from ethereum.utils.numeric import ceil32
from tests.utils.strategies import uint128


class TestMaths:
    @given(uint128, st.integers(min_value=1, max_value=DEFAULT_PRIME // 2**128))
    def test_should_unsigned_div_rem(self, cairo_run, value, div):
        assert list(divmod(value, div)) == cairo_run(
            "test__unsigned_div_rem", value=value, div=div
        )

    @given(uint128)
    def test_should_ceil32(self, cairo_run, value):
        assert ceil32(value) == cairo_run("test__ceil32", value=value)

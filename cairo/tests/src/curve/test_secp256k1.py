import hypothesis.strategies as st
import pytest
from hypothesis import given
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME
from sympy import sqrt_mod

from src.utils.uint384 import int_to_uint384, uint384_to_int

pytestmark = pytest.mark.python_vm
A = 0
B = 7
G = 3
P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141


class TestSecp256k1:

    class TestGetGeneratorPoint:
        def test_get_generator_point(self, cairo_run):
            cairo_run("test__get_generator_point")

    class TestTryGetPointFromX:
        @given(
            x=st.integers(min_value=0, max_value=2**384 - 1),
            v=st.integers(min_value=0, max_value=DEFAULT_PRIME - 1),
        )
        def test_try_get_point_from_x(self, cairo_run, x, v):
            y_try, is_on_curve = cairo_run(
                "test__try_get_point_from_x", x=int_to_uint384(x % P), v=v
            )

            square_root = sqrt_mod(x**3 + A * x + B, P)
            assert (square_root is not None) == is_on_curve
            if square_root is not None:
                assert (
                    square_root if (v % 2 == square_root % 2) else (-square_root % P)
                ) == uint384_to_int(y_try["d0"], y_try["d1"], y_try["d2"], y_try["d3"])

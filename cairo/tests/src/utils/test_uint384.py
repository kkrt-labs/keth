import pytest
from hypothesis import given
from hypothesis.strategies import integers

from src.utils.uint256 import int_to_uint256, uint256_to_int
from src.utils.uint384 import int_to_uint384, uint384_to_int

pytestmark = pytest.mark.python_vm


class TestUint384:

    class TestUint256ToUint384:
        @given(a=integers(min_value=0, max_value=2**256 - 1))
        def test_should_pass_if_fits_in_256_bits(self, cairo_run, a):
            res = cairo_run("test__uint256_to_uint384", a=int_to_uint256(a))
            assert uint384_to_int(res["d0"], res["d1"], res["d2"], res["d3"]) == a

    class TestUint384ToUint256:
        @given(a=integers(min_value=0, max_value=2**256 - 1))
        def test_should_pass_if_fits_in_256_bits(self, cairo_run, a):
            res = cairo_run("test__uint384_to_uint256", a=int_to_uint384(a))
            assert uint256_to_int(res["low"], res["high"]) == a

        @given(a=integers(min_value=2**256, max_value=2**384 - 1))
        def test_should_fail_if_does_not_fit_in_256_bits(self, cairo_run, a):
            with pytest.raises(Exception):
                cairo_run("test__uint384_to_uint256", a=int_to_uint384(a))

    class TestAssertUint384Le:
        @given(
            a=integers(min_value=0, max_value=2**384 - 1),
            b=integers(min_value=0, max_value=2**384 - 1),
        )
        def test_assert_uint384_le(self, cairo_run, a, b):
            if a > b:
                with pytest.raises(Exception):
                    cairo_run(
                        "test__assert_uint384_le",
                        a=int_to_uint384(a),
                        b=int_to_uint384(b),
                    )
            else:
                cairo_run(
                    "test__assert_uint384_le", a=int_to_uint384(a), b=int_to_uint384(b)
                )

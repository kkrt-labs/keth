import pytest
from hypothesis import assume, given, settings
from hypothesis.strategies import integers
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

from cairo_addons.testing.strategies import felt, uint128
from src.utils.uint256 import int_to_uint256

pytestmark = pytest.mark.python_vm


class TestMaths:

    class TestSign:
        @given(value=felt)
        def test_sign(self, cairo_run, value):
            assume(value != 0)
            sign = cairo_run("test__sign", value=value)
            assert (
                sign % DEFAULT_PRIME
                == (2 * (0 <= value < DEFAULT_PRIME // 2) - 1) % DEFAULT_PRIME
            )

    class TestScalarToEpns:
        @given(scalar=uint128)
        def test_scalar_to_epns(self, cairo_run, scalar):
            sum_p, sum_n, p_sign, n_sign = cairo_run(
                "test__scalar_to_epns", scalar=scalar
            )
            assert (
                sum_p * p_sign - sum_n * n_sign
            ) % DEFAULT_PRIME == scalar % DEFAULT_PRIME

    class TestAssertUint256Le:
        @given(
            a=integers(min_value=0, max_value=2**256 - 1),
            b=integers(min_value=0, max_value=2**256 - 1),
        )
        @settings(max_examples=50)
        def test_assert_uint256_le(self, cairo_run, a, b):
            if a > b:
                with pytest.raises(Exception):
                    cairo_run(
                        "test__assert_uint256_le",
                        a=int_to_uint256(a),
                        b=int_to_uint256(b),
                    )
            else:
                cairo_run(
                    "test__assert_uint256_le", a=int_to_uint256(a), b=int_to_uint256(b)
                )

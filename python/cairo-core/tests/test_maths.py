import pytest
from hypothesis import assume, given
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

from cairo_addons.testing.strategies import felt, uint128

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

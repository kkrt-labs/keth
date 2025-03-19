from hypothesis import given
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

from cairo_addons.testing.strategies import uint128


class TestScalarToEpns:
    @given(scalar=uint128)
    def test_scalar_to_epns(self, cairo_run, scalar):
        sum_p, sum_n, p_sign, n_sign = cairo_run("scalar_to_epns", scalar=scalar)
        assert (
            sum_p * p_sign - sum_n * n_sign
        ) % DEFAULT_PRIME == scalar % DEFAULT_PRIME

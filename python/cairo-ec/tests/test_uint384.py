import pytest
from ethereum.crypto.elliptic_curve import SECP256K1N
from ethereum_types.numeric import U256
from hypothesis import assume, given
from hypothesis import strategies as st
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

from cairo_addons.testing.errors import strict_raises
from tests.utils.args_gen import U384


class TestUint384:

    class TestUint256ToUint384:
        @given(a=...)
        def test_should_pass(self, cairo_run, a: U256):
            res = cairo_run("test__uint256_to_uint384", a=a)
            assert res == a

    class TestUint384ToUint256:
        @given(a=st.integers(min_value=0, max_value=2**256 - 1).map(U384))
        def test_should_pass_if_fits_in_256_bits(self, cairo_run, a: U384):
            res = cairo_run("test__uint384_to_uint256", a=a)
            assert res == a

        @given(a=st.integers(min_value=2**256, max_value=2**384 - 1).map(U384))
        def test_should_fail_if_does_not_fit_in_256_bits(self, cairo_run, a: U384):
            with strict_raises(AssertionError):
                cairo_run("test__uint384_to_uint256", a=a)

    class TestAssertUint384Le:
        @given(a=..., b=...)
        def test_uint384_assert_le(self, cairo_run, a: U384, b: U384):
            if a > b:
                with pytest.raises(Exception):
                    cairo_run("test__uint384_assert_le", a=a, b=b)
            else:
                cairo_run("test__uint384_assert_le", a=a, b=b)

    class TestEqModP:
        @given(
            x=...,
            y=...,
            p=st.one_of(st.just(DEFAULT_PRIME), st.just(int(SECP256K1N))).map(U384),
        )
        def test_should_return_false_if_x_neq_y_mod_p(
            self, cairo_run, x: U384, y: U384, p: U384
        ):
            assume(x % p != y % p)
            assert not cairo_run(
                "test__uint384_eq_mod_p",
                x=x % p,
                y=y % p,
                p=p,
            )

        @given(
            x=...,
            p=st.one_of(st.just(DEFAULT_PRIME), st.just(int(SECP256K1N))).map(U384),
        )
        def test_should_return_true_if_x_eq_y_mod_p(self, cairo_run, x: U384, p: U384):
            assert cairo_run(
                "test__uint384_eq_mod_p",
                x=x % p,
                y=x % p,
                p=p,
            )

    class TestIsNegModP:
        @given(
            x=...,
            p=st.one_of(st.just(DEFAULT_PRIME), st.just(int(SECP256K1N))).map(U384),
        )
        def test_should_return_true_if_x_eq_neg_y_mod_p(
            self, cairo_run, x: U384, p: U384
        ):
            assert cairo_run(
                "test__uint384_is_neg_mod_p",
                x=x % p,
                y=U384(-x % p._number),
                p=p,
            )

        @given(
            x=...,
            y=...,
            p=st.one_of(st.just(DEFAULT_PRIME), st.just(int(SECP256K1N))).map(U384),
        )
        def test_should_return_false_if_x_neq_neg_y_mod_p(
            self, cairo_run, x: U384, y: U384, p: U384
        ):
            assume(x % p != U384(-y % p._number))
            assert not cairo_run(
                "test__uint384_is_neg_mod_p",
                x=x % p,
                y=y % p,
                p=p,
            )

    class TestFeltToUint384:
        @given(x=st.integers(min_value=0, max_value=DEFAULT_PRIME - 1))
        def test_should_pass(self, cairo_run, x):
            res = cairo_run("test__felt_to_uint384", x=x)
            assert res._number == x

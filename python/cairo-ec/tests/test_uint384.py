import pytest
from ethereum.crypto.elliptic_curve import SECP256K1N
from hypothesis import assume, given
from hypothesis import strategies as st
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

from cairo_addons.utils.uint256 import int_to_uint256, uint256_to_int
from cairo_addons.utils.uint384 import int_to_uint384, uint384_to_int

pytestmark = pytest.mark.python_vm


class TestUint384:

    class TestUint256ToUint384:
        @given(a=st.integers(min_value=0, max_value=2**256 - 1))
        def test_should_pass(self, cairo_run, a):
            res = cairo_run("test__uint256_to_uint384", a=int_to_uint256(a))
            assert uint384_to_int(res["d0"], res["d1"], res["d2"], res["d3"]) == a

    class TestUint384ToUint256:
        @given(a=st.integers(min_value=0, max_value=2**256 - 1))
        def test_should_pass_if_fits_in_256_bits(self, cairo_run, a):
            res = cairo_run("test__uint384_to_uint256", a=int_to_uint384(a))
            assert uint256_to_int(res["low"], res["high"]) == a

        @given(a=st.integers(min_value=2**256, max_value=2**384 - 1))
        def test_should_fail_if_does_not_fit_in_256_bits(self, cairo_run, a):
            with pytest.raises(Exception):
                cairo_run("test__uint384_to_uint256", a=int_to_uint384(a))

    class TestAssertUint384Le:
        @given(
            a=st.integers(min_value=0, max_value=2**384 - 1),
            b=st.integers(min_value=0, max_value=2**384 - 1),
        )
        def test_uint384_assert_le(self, cairo_run, a, b):
            if a > b:
                with pytest.raises(Exception):
                    cairo_run(
                        "test__uint384_assert_le",
                        a=int_to_uint384(a),
                        b=int_to_uint384(b),
                    )
            else:
                cairo_run(
                    "test__uint384_assert_le", a=int_to_uint384(a), b=int_to_uint384(b)
                )

    class TestAssertNeqModP:
        @given(
            x=st.integers(min_value=0, max_value=2**384 - 1),
            y=st.integers(min_value=0, max_value=2**384 - 1),
            p=st.one_of(st.just(DEFAULT_PRIME), st.just(int(SECP256K1N))),
        )
        def test_should_pass_if_x_neq_y_mod_p(self, cairo_run, x, y, p):
            diff = (x - y) % p
            assume(diff != 0)
            assume(pow(diff, -1, p))
            cairo_run(
                "test__uint384_assert_neq_mod_p",
                x=int_to_uint384(x % p),
                y=int_to_uint384(y % p),
                p=int_to_uint384(p),
            )

        @given(
            x=st.integers(min_value=0, max_value=2**384 - 1),
            p=st.one_of(st.just(DEFAULT_PRIME), st.just(int(SECP256K1N))),
        )
        def test_should_fail_if_x_eq_y_mod_p(self, cairo_run, x, p):
            with pytest.raises(Exception):
                cairo_run(
                    "test__uint384_assert_neq_mod_p",
                    x=int_to_uint384(x % p),
                    y=int_to_uint384(x % p),
                    p=int_to_uint384(p),
                )

    class TestAssertEqModP:
        @given(
            x=st.integers(min_value=0, max_value=2**384 - 1),
            y=st.integers(min_value=0, max_value=2**384 - 1),
            p=st.one_of(st.just(DEFAULT_PRIME), st.just(int(SECP256K1N))),
        )
        def test_should_fail_if_x_neq_y_mod_p(self, cairo_run, x, y, p):
            diff = (x - y) % p
            assume(diff != 0)
            assume(pow(diff, -1, p))
            with pytest.raises(Exception):
                cairo_run(
                    "test__uint384_assert_eq_mod_p",
                    x=int_to_uint384(x % p),
                    y=int_to_uint384(y % p),
                    p=int_to_uint384(p),
                )

        @given(
            x=st.integers(min_value=0, max_value=2**384 - 1),
            p=st.one_of(st.just(DEFAULT_PRIME), st.just(int(SECP256K1N))),
        )
        def test_should_pass_if_x_eq_y_mod_p(self, cairo_run, x, p):
            cairo_run(
                "test__uint384_assert_eq_mod_p",
                x=int_to_uint384(x % p),
                y=int_to_uint384(x % p),
                p=int_to_uint384(p),
            )

    class TestEqModP:
        @given(
            x=st.integers(min_value=0, max_value=2**384 - 1),
            y=st.integers(min_value=0, max_value=2**384 - 1),
            p=st.one_of(st.just(DEFAULT_PRIME), st.just(int(SECP256K1N))),
        )
        def test_should_return_false_if_x_neq_y_mod_p(self, cairo_run, x, y, p):
            assume(x % p != y % p)
            assert not cairo_run(
                "test__uint384_eq_mod_p",
                x=int_to_uint384(x % p),
                y=int_to_uint384(y % p),
                p=int_to_uint384(p),
            )

        @given(
            x=st.integers(min_value=0, max_value=2**384 - 1),
            p=st.one_of(st.just(DEFAULT_PRIME), st.just(int(SECP256K1N))),
        )
        def test_should_return_true_if_x_eq_y_mod_p(self, cairo_run, x, p):
            assert cairo_run(
                "test__uint384_eq_mod_p",
                x=int_to_uint384(x % p),
                y=int_to_uint384(x % p),
                p=int_to_uint384(p),
            )

    class TestAssertNegModP:
        @given(
            x=st.integers(min_value=0, max_value=2**384 - 1),
            p=st.one_of(st.just(DEFAULT_PRIME), st.just(int(SECP256K1N))),
        )
        def test_should_pass_if_x_eq_neg_y_mod_p(self, cairo_run, x, p):
            cairo_run(
                "test__uint384_assert_neg_mod_p",
                x=int_to_uint384(x % p),
                y=int_to_uint384(-x % p),
                p=int_to_uint384(p),
            )

        @given(
            x=st.integers(min_value=0, max_value=2**384 - 1),
            y=st.integers(min_value=0, max_value=2**384 - 1),
            p=st.one_of(st.just(DEFAULT_PRIME), st.just(int(SECP256K1N))),
        )
        def test_should_fail_if_x_neq_neg_y_mod_p(self, cairo_run, x, y, p):
            assume(x % p != -y % p)
            with pytest.raises(Exception):
                cairo_run(
                    "test__uint384_assert_neg_mod_p",
                    x=int_to_uint384(x % p),
                    y=int_to_uint384(y % p),
                    p=int_to_uint384(p),
                )

    class TestAssertNotNegModP:
        @given(
            x=st.integers(min_value=0, max_value=2**384 - 1),
            y=st.integers(min_value=0, max_value=2**384 - 1),
            p=st.one_of(st.just(DEFAULT_PRIME), st.just(int(SECP256K1N))),
        )
        def test_should_pass_if_x_neq_neg_y_mod_p(self, cairo_run, x, y, p):
            assume(x % p != -y % p)
            cairo_run(
                "test__uint384_assert_not_neg_mod_p",
                x=int_to_uint384(x % p),
                y=int_to_uint384(y % p),
                p=int_to_uint384(p),
            )

        @given(
            x=st.integers(min_value=0, max_value=2**384 - 1),
            p=st.one_of(st.just(DEFAULT_PRIME), st.just(int(SECP256K1N))),
        )
        def test_should_fail_if_x_eq_neg_y_mod_p(self, cairo_run, x, p):
            with pytest.raises(Exception):
                cairo_run(
                    "test__uint384_assert_not_neg_mod_p",
                    x=int_to_uint384(x % p),
                    y=int_to_uint384(-x % p),
                    p=int_to_uint384(p),
                )

    class TestIsNegModP:
        @given(
            x=st.integers(min_value=0, max_value=2**384 - 1),
            p=st.one_of(st.just(DEFAULT_PRIME), st.just(int(SECP256K1N))),
        )
        def test_should_return_true_if_x_eq_neg_y_mod_p(self, cairo_run, x, p):
            assert cairo_run(
                "test__uint384_is_neg_mod_p",
                x=int_to_uint384(x % p),
                y=int_to_uint384(-x % p),
                p=int_to_uint384(p),
            )

        @given(
            x=st.integers(min_value=0, max_value=2**384 - 1),
            y=st.integers(min_value=0, max_value=2**384 - 1),
            p=st.one_of(st.just(DEFAULT_PRIME), st.just(int(SECP256K1N))),
        )
        def test_should_return_false_if_x_neq_neg_y_mod_p(self, cairo_run, x, y, p):
            assume(x % p != -y % p)
            assert not cairo_run(
                "test__uint384_is_neg_mod_p",
                x=int_to_uint384(x % p),
                y=int_to_uint384(y % p),
                p=int_to_uint384(p),
            )

    class TestDivModP:
        @given(
            x=st.integers(min_value=0, max_value=2**384 - 1),
            y=st.integers(min_value=1, max_value=2**384 - 1),
            p=st.one_of(st.just(DEFAULT_PRIME), st.just(int(SECP256K1N))),
        )
        def test_should_pass(self, cairo_run, x, y, p):
            res = cairo_run(
                "test__uint384_div_mod_p",
                x=int_to_uint384(x % p),
                y=int_to_uint384(y % p),
                p=int_to_uint384(p),
            )
            y_inv = pow(y, -1, p)
            assert (
                uint384_to_int(res["d0"], res["d1"], res["d2"], res["d3"])
                == (x * y_inv) % p
            )

    class TestNegModP:
        @given(
            y=st.integers(min_value=0, max_value=2**384 - 1),
            p=st.one_of(st.just(DEFAULT_PRIME), st.just(int(SECP256K1N))),
        )
        def test_should_pass(self, cairo_run, y, p):
            res = cairo_run(
                "test__uint384_neg_mod_p", y=int_to_uint384(y % p), p=int_to_uint384(p)
            )
            assert uint384_to_int(res["d0"], res["d1"], res["d2"], res["d3"]) == -y % p

    class TestFeltToUint384:
        @given(x=st.integers(min_value=0, max_value=DEFAULT_PRIME - 1))
        def test_should_pass(self, cairo_run, x):
            res = cairo_run("test__felt_to_uint384", x=x)
            assert uint384_to_int(res["d0"], res["d1"], res["d2"], res["d3"]) == x

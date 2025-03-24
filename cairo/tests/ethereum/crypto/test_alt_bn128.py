import pytest
from ethereum.crypto.alt_bn128 import BNF, BNF2, BNF12, BNP, BNP2, BNP12, bnf2_to_bnf12
from hypothesis import assume, given

from cairo_addons.testing.errors import strict_raises
from cairo_addons.testing.hints import patch_hint
from cairo_ec.curve import AltBn128
from tests.utils.args_gen import U384


class TestAltBn128:
    class TestBNP:
        def test_bnp_init(self, cairo_run):
            p = AltBn128.random_point()
            assert cairo_run("bnp_init", BNF(p.x), BNF(p.y)) == BNP(p.x, p.y)

        @given(x=..., y=...)
        def test_bnp_init_fails(self, cairo_run, x: BNF, y: BNF):
            with pytest.raises(Exception):
                cairo_run("bnp_init", x, y)

    class TestBNF2:
        @given(a=..., b=...)
        def test_bnf2_add(self, cairo_run, a: BNF2, b: BNF2):
            assert cairo_run("bnf2_add", a, b) == a + b

        @given(a=..., b=...)
        def test_bnf2_sub(self, cairo_run, a: BNF2, b: BNF2):
            assert cairo_run("bnf2_sub", a, b) == a - b

        @given(a=..., b=...)
        def test_bnf2_mul(self, cairo_run, a: BNF2, b: BNF2):
            assert cairo_run("bnf2_mul", a, b) == a * b

        @given(a=..., b=...)
        def test_bnf2_div(self, cairo_run, a: BNF2, b: BNF2):
            assume(b != BNF2.zero())
            # A bug in the EELS implementation requires this assumption for now.
            # https://github.com/kkrt-labs/keth/issues/1099#issue-2946095802
            assume(b.multiplicative_inverse != BNF2.zero())
            assert cairo_run("bnf2_div", a, b) == a / b

        @given(a=...)
        def test_bnf2_div_by_zero_should_fail(self, cairo_run, a: BNF2):
            b = BNF2.zero()
            with pytest.raises(Exception):
                cairo_run("bnf2_div", a, b)

        @given(a=..., b=...)
        def test_bnf2_div_patch_hint_should_fail(
            self, cairo_programs, cairo_run_py, a: BNF2, b: BNF2
        ):
            assume(b != BNF2.zero())
            assume(b.multiplicative_inverse() != BNF2.zero())
            with patch_hint(
                cairo_programs,
                "bnf2_multiplicative_inverse",
                """
from cairo_addons.utils.uint384 import int_to_uint384

bnf2_struct_ptr = segments.add(2)
b_inv_c0_ptr = segments.gen_arg(int_to_uint384(0))
b_inv_c1_ptr = segments.gen_arg(int_to_uint384(0))
segments.load_data(bnf2_struct_ptr, [b_inv_c0_ptr, b_inv_c1_ptr])
segments.load_data(ids.b_inv.address_, [bnf2_struct_ptr])
                """,
            ), strict_raises(AssertionError):
                cairo_run_py("bnf2_div", a, b)

        @given(a=..., b=...)
        def test_bnf2_eq(self, cairo_run, a: BNF2, b: BNF2):
            assert cairo_run("BNF2__eq__", a, b) == (a == b)

        def test_BNF2_ZERO(self, cairo_run):
            assert cairo_run("BNF2_ZERO") == BNF2.zero()

        def test_BNF2_ONE(self, cairo_run):
            assert cairo_run("BNF2_ONE") == BNF2.from_int(1)

    class TestBNP2:
        def test_bnp2_point_at_infinity(self, cairo_run):
            assert cairo_run("bnp2_point_at_infinity") == BNP2.point_at_infinity()

        @given(p=...)
        def test_bnp2_double(self, cairo_run, p: BNP2):
            assert cairo_run("bnp2_double", p) == p.double()

    class TestBNF12:
        def test_FROBENIUS_COEFFICIENTS(self, cairo_run):
            cairo_coeffs = cairo_run("FROBENIUS_COEFFICIENTS")
            assert len(cairo_coeffs) == 12
            frob_coeffs = tuple(
                BNF12(BNF12.FROBENIUS_COEFFICIENTS[i]) for i in range(12)
            )
            assert all(cairo_coeffs[i] == coeff for i, coeff in enumerate(frob_coeffs))

        def test_BNF12_W(self, cairo_run):
            cairo_w = cairo_run("BNF12_W")
            assert cairo_w == BNF12.w

        def test_BNF12_W_POW_2(self, cairo_run):
            cairo_w_pow_2 = cairo_run("BNF12_W_POW_2")
            assert cairo_w_pow_2 == BNF12.w**2

        def test_BNF12_W_POW_3(self, cairo_run):
            cairo_w_pow_3 = cairo_run("BNF12_W_POW_3")
            assert cairo_w_pow_3 == BNF12.w**3

        def test_BNF12_I_PLUS_9(self, cairo_run):
            cairo_i_plus_9 = cairo_run("BNF12_I_PLUS_9")
            assert cairo_i_plus_9 == BNF12.i_plus_9

        def test_BNF12_ZERO(self, cairo_run):
            cairo_zero = cairo_run("BNF12_ZERO")
            assert cairo_zero == BNF12.zero()

        @given(a=..., b=...)
        def test_bnf12_add(self, cairo_run, a: BNF12, b: BNF12):
            assert cairo_run("bnf12_add", a, b) == a + b

        @given(a=..., b=...)
        def test_bnf12_sub(self, cairo_run, a: BNF12, b: BNF12):
            assert cairo_run("bnf12_sub", a, b) == a - b

        @given(a=..., x=...)
        def test_bnf12_scalar_mul(self, cairo_run, a: BNF12, x: U384):
            assert cairo_run("bnf12_scalar_mul", a, x) == a.scalar_mul(int(x))

        @given(x=...)
        def test_bnf12_from_int(self, cairo_run, x: U384):
            cairo_result = cairo_run("bnf12_from_int", x)
            assert cairo_result == BNF12.from_int(int(x))

        @given(a=..., b=...)
        def test_bnf12_mul(self, cairo_run, a: BNF12, b: BNF12):
            cairo_result = cairo_run("bnf12_mul", a, b)
            assert cairo_result == a * b

        def test_bnf12_ONE(self, cairo_run):
            cairo_one = cairo_run("bnf12_ONE")
            assert cairo_one == BNF12.from_int(1)

        @given(a=..., b=...)
        def test_bnf12_pow(self, cairo_run, a: BNF12, b: U384):
            assert cairo_run("bnf12_pow", a, b) == a ** int(b)

        @given(a=..., b=...)
        def test_bnf12_eq(self, cairo_run, a: BNF12, b: BNF12):
            assert cairo_run("BNF12__eq__", a, b) == (a == b)

        @given(a=...)
        def test_bnf12_frobenius(self, cairo_run, a: BNF12):
            assert cairo_run("bnf12_frobenius", a) == a.frobenius()

    class TestBNP12:
        def test_A(self, cairo_run):
            cairo_a = cairo_run("A")
            assert cairo_a == BNP12.A

        def test_B(self, cairo_run):
            cairo_b = cairo_run("B")
            assert cairo_b == BNP12.B

        def test_bnp12_point_at_infinity(self, cairo_run):
            cairo_infinity = cairo_run("bnp12_point_at_infinity")
            assert cairo_infinity == BNP12.point_at_infinity()

        @given(a=..., b=...)
        def test_bnp12_eq(self, cairo_run, a: BNP12, b: BNP12):
            assert cairo_run("BNP12__eq__", a, b) == (a == b)

    class TestUtils:
        @given(x=...)
        def test_bnf2_to_bnf12(self, cairo_run, x: BNF2):
            assert cairo_run("bnf2_to_bnf12", x) == bnf2_to_bnf12(x)

        @given(x=...)
        def test_bnp_to_bnp12(self, cairo_run, x: BNP):
            from ethereum.crypto.alt_bn128 import bnp_to_bnp12

            assert cairo_run("bnp_to_bnp12", x) == bnp_to_bnp12(x)

        @given(x=...)
        def test_twist(self, cairo_run, x: BNP2):
            from ethereum.crypto.alt_bn128 import twist

            assert cairo_run("twist", x) == twist(x)

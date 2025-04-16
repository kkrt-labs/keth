import pytest
from ethereum.crypto.alt_bn128 import (
    BNF,
    BNF2,
    BNF12,
    BNP,
    BNP2,
    pairing,
)
from hypothesis import assume, given, settings

from cairo_addons.testing.errors import cairo_error, strict_raises
from cairo_addons.testing.hints import patch_hint
from tests.utils.args_gen import U384

# https://github.com/keep-starknet-strange/garaga/blob/704a8c66bf85b965851a117c6b116fc7a11329db/hydra/garaga/definitions.py#L346
# see test_pairing
GARAGA_COFACTOR = 0x3BEC47DF15E307C81EA96B02D9D9E38D2E5D4E223DDEDAF4


class TestAltBn128:
    class TestBNF:
        def test_bnf_zero(self, cairo_run):
            assert cairo_run("BNF_ZERO") == BNF.zero()

        @given(a=..., b=...)
        def test_bnf_eq(self, cairo_run, a: BNF, b: BNF):
            assert cairo_run("BNF__eq__", a, b) == (a == b)

        @given(a=..., b=...)
        def test_bnf_mul(self, cairo_run, a: BNF, b: BNF):
            assert cairo_run("bnf_mul", a, b) == a * b

        @given(a=..., b=...)
        def test_bnf_sub(self, cairo_run, a: BNF, b: BNF):
            assert cairo_run("bnf_sub", a, b) == a - b

        @given(a=..., b=...)
        def test_bnf_add(self, cairo_run, a: BNF, b: BNF):
            assert cairo_run("bnf_add", a, b) == a + b

        @given(a=..., b=...)
        def test_bnf_div(self, cairo_run, a: BNF, b: BNF):
            assume(b != BNF.zero())  # Avoid division by zero
            assert cairo_run("bnf_div", a, b) == a / b

        @given(a=...)
        def test_bnf_div_by_zero_should_fail(self, cairo_run, a: BNF):
            b = BNF.zero()
            with strict_raises(AssertionError):
                cairo_run("bnf_div", a, b)

        @given(a=..., b=...)
        def test_bnf_div_patch_hint_should_fail(
            self, cairo_programs, rust_programs, cairo_run, a: BNF, b: BNF
        ):
            assume(b != BNF.zero())
            with patch_hint(
                cairo_programs,
                rust_programs,
                "bnf_multiplicative_inverse",
                """
from cairo_addons.utils.uint384 import int_to_uint384

bnf_struct_ptr = segments.add()
b_inv_u384_ptr = segments.gen_arg(int_to_uint384(0))  # Wrong inverse value
segments.load_data(bnf_struct_ptr, [b_inv_u384_ptr])
segments.load_data(ids.b_inv.address_, [bnf_struct_ptr])
                """,
            ), strict_raises(AssertionError):
                cairo_run("bnf_div", a, b)

    class TestBNP:
        @given(p=...)
        def test_bnp_init(self, cairo_run, p: BNP):
            assert cairo_run("bnp_init", BNF(p.x), BNF(p.y)) == BNP(p.x, p.y)

        @given(x=..., y=...)
        def test_bnp_init_fails(self, cairo_run, x: BNF, y: BNF):
            assume(x != BNF.zero() or y != BNF.zero())
            with strict_raises(ValueError):
                cairo_run("bnp_init", x, y)
            with pytest.raises(ValueError):
                BNP(x, y)

        def test_bnp_point_at_infinity(self, cairo_run):
            assert cairo_run("bnp_point_at_infinity") == BNP.point_at_infinity()

        @given(a=..., b=...)
        def test_bnp_eq(self, cairo_run, a: BNP, b: BNP):
            assert cairo_run("BNP__eq__", a, b) == (a == b)

        @given(p=..., q=...)
        def test_bnp_add(self, cairo_run, p: BNP, q: BNP):
            assert cairo_run("bnp_add", p, q) == p + q

        @given(p=...)
        def test_bnp_double(self, cairo_run, p: BNP):
            assert cairo_run("bnp_double", p) == p.double()

        @given(p=..., n=...)
        def test_bnp_mul_by(self, cairo_run, p: BNP, n: U384):
            assert cairo_run("bnp_mul_by", p, n) == p.mul_by(int(n))

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
            assume(b.multiplicative_inverse() != BNF2.zero())
            assert cairo_run("bnf2_div", a, b) == a / b

        @given(a=...)
        def test_bnf2_div_by_zero_should_fail(self, cairo_run, a: BNF2):
            b = BNF2.zero()
            with strict_raises(AssertionError):
                cairo_run("bnf2_div", a, b)

        @given(a=..., b=...)
        def test_bnf2_div_patch_hint_should_fail(
            self, cairo_programs, rust_programs, cairo_run, a: BNF2, b: BNF2
        ):
            assume(b != BNF2.zero())
            assume(b.multiplicative_inverse() != BNF2.zero())
            with patch_hint(
                cairo_programs,
                rust_programs,
                "bnf2_multiplicative_inverse",
                """
from cairo_addons.utils.uint384 import int_to_uint384

bnf2_struct_ptr = segments.add()
b_inv_c0_ptr = segments.gen_arg(int_to_uint384(0))
b_inv_c1_ptr = segments.gen_arg(int_to_uint384(0))
segments.load_data(bnf2_struct_ptr, [b_inv_c0_ptr, b_inv_c1_ptr])
segments.load_data(ids.b_inv.address_, [bnf2_struct_ptr])
                """,
            ), strict_raises(AssertionError):
                cairo_run("bnf2_div", a, b)

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

        def test_BNP2_B(self, cairo_run):
            assert cairo_run("BNP2_B") == BNP2.B

        @given(p=...)
        def test_bnp2_init(self, cairo_run, p: BNP2):
            assert cairo_run("bnp2_init", p.x, p.y) == p

        @given(x=..., y=...)
        def test_bnp2_init_fails(self, cairo_run, x: BNF2, y: BNF2):
            assume(x != BNF2.zero() or y != BNF2.zero())
            with strict_raises(ValueError):
                cairo_run("bnp2_init", x, y)
            with pytest.raises(ValueError):
                BNP2(x, y)

        @given(a=..., b=...)
        def test_bnp2_eq(self, cairo_run, a: BNP2, b: BNP2):
            assert cairo_run("BNP2__eq__", a, b) == (a == b)

        @given(p=...)
        def test_bnp2_double(self, cairo_run, p: BNP2):
            assert cairo_run("bnp2_double", p) == p.double()

        @given(p=...)
        def test_bnp2_add_negated_y(self, cairo_run, p: BNP2):
            q = BNP2(p.x, -p.y)
            assert cairo_run("bnp2_add", p, q) == BNP2.point_at_infinity()

        @given(p=..., q=...)
        def test_bnp2_add(self, cairo_run, p: BNP2, q: BNP2):
            assert cairo_run("bnp2_add", p, q) == p + q

        @given(p=..., n=...)
        @pytest.mark.slow
        def test_bnp2_mul_by(self, cairo_run, p: BNP2, n: U384):
            assert cairo_run("bnp2_mul_by", p, n) == p.mul_by(int(n))

    class TestBNF12:

        def test_BNF12_ZERO(self, cairo_run):
            cairo_zero = cairo_run("BNF12_ZERO")
            assert cairo_zero == BNF12.zero()

        def test_BNF12_ONE(self, cairo_run):
            cairo_one = cairo_run("BNF12_ONE")
            assert cairo_one == BNF12.from_int(1)

        @given(a=..., b=...)
        def test_bnf12_mul(self, cairo_run, a: BNF12, b: BNF12):
            cairo_result = cairo_run("bnf12_mul", a, b)
            assert cairo_result == a * b

        @given(a=..., b=...)
        def test_bnf12_eq(self, cairo_run, a: BNF12, b: BNF12):
            assert cairo_run("BNF12__eq__", a, b) == (a == b)

    class TestUtils:
        @given(p=..., q=...)
        @settings(max_examples=10)
        @pytest.mark.slow
        # Garaga final exponentiation match the gnark one which uses a cofactor
        # This does not affect the pairing properties
        # https://github.com/keep-starknet-strange/garaga/blob/704a8c66bf85b965851a117c6b116fc7a11329db/hydra/garaga/definitions.py#L346
        # https://github.com/Consensys/gnark/blob/bd4a39719a964f0305ee9ec36b6226e4c266584c/std/algebra/emulated/sw_bn254/pairing.go#L129
        def test_pairing(self, cairo_run, p: BNP, q: BNP2):
            assume(p.x != BNF.zero())
            assume(q.x != BNF2.zero())
            try:
                expected = pairing(q, p) ** GARAGA_COFACTOR
            except OverflowError:  # fails for large points
                with cairo_error(message="OverflowError"):  # Hint error
                    cairo_run("pairing", q, p)
                return
            assert cairo_run("pairing", q, p) == expected

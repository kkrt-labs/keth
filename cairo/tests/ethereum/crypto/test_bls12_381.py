import pytest
from hypothesis import assume, given
from py_ecc.fields import optimized_bls12_381_FQ as BLSF
from py_ecc.fields import optimized_bls12_381_FQ2 as BLSF2
from py_ecc.optimized_bls12_381.optimized_curve import (
    Z1,
    add,
    double,
    eq,
    is_inf,
    multiply,
)
from py_ecc.optimized_bls12_381.optimized_pairing import normalize1
from py_ecc.typing import Optimized_Point3D

from cairo_addons.testing.errors import strict_raises
from cairo_addons.testing.hints import patch_hint
from tests.utils.args_gen import U384


class TestBls12381:
    class TestBLSF:
        def test_blsf_zero(self, cairo_run):
            assert cairo_run("BLSF_ZERO") == BLSF.zero()

        @given(a=..., b=...)
        def test_blsf_add(self, cairo_run, a: BLSF, b: BLSF):
            assert cairo_run("blsf_add", a, b) == a + b

        @given(a=..., b=...)
        def test_blsf_sub(self, cairo_run, a: BLSF, b: BLSF):
            assert cairo_run("blsf_sub", a, b) == a - b

        @given(a=..., b=...)
        def test_blsf_eq(self, cairo_run, a: BLSF, b: BLSF):
            assert cairo_run("BLSF__eq__", a, b) == (a == b)

        @given(a=..., b=...)
        def test_blsf_mul(self, cairo_run, a: BLSF, b: BLSF):
            assert cairo_run("blsf_mul", a, b) == a * b

        @given(a=..., b=...)
        def test_blsf_div(self, cairo_run, a: BLSF, b: BLSF):
            assume(b != BLSF.zero())  # Avoid division by zero
            assert cairo_run("blsf_div", a, b) == a / b

        @given(a=...)
        def test_blsf_div_by_zero_should_fail(self, cairo_run, a: BLSF):
            b = BLSF.zero()
            with strict_raises(AssertionError):
                cairo_run("blsf_div", a, b)

        @given(a=..., b=...)
        @pytest.mark.slow
        def test_blsf_div_patch_hint_should_fail(
            self, cairo_programs, cairo_run_py, a: BLSF, b: BLSF
        ):
            assume(b != BLSF.zero())
            with patch_hint(
                cairo_programs,
                "blsf_multiplicative_inverse",
                """
from cairo_addons.utils.uint384 import int_to_uint384

blsf_struct_ptr = segments.add()
b_inv_u384_ptr = segments.gen_arg(int_to_uint384(0))  # Wrong inverse value
segments.load_data(blsf_struct_ptr, [b_inv_u384_ptr])
segments.load_data(ids.b_inv.address_, [blsf_struct_ptr])
                """,
            ), strict_raises(AssertionError):
                cairo_run_py("blsf_div", a, b)

    class TestBLSF2:

        def test_BLSF2_ZERO(self, cairo_run):
            assert cairo_run("BLSF2_ZERO") == BLSF2.zero()

        def test_BLSF2_ONE(self, cairo_run):
            assert cairo_run("BLSF2_ONE") == BLSF2.one()

        @given(a=..., b=...)
        def test_blsf2_eq(self, cairo_run, a: BLSF2, b: BLSF2):
            assert cairo_run("BLSF2__eq__", a, b) == (a == b)

        @given(a=..., b=...)
        def test_blsf2_add(self, cairo_run, a: BLSF2, b: BLSF2):
            assert cairo_run("blsf2_add", a, b) == a + b

        @given(a=..., b=...)
        def test_blsf2_sub(self, cairo_run, a: BLSF2, b: BLSF2):
            assert cairo_run("blsf2_sub", a, b) == a - b

        @given(a=..., b=...)
        def test_blsf2_mul(self, cairo_run, a: BLSF2, b: BLSF2):
            assert cairo_run("blsf2_mul", a, b) == a * b

        @given(a=..., b=...)
        def test_blsf2_div(self, cairo_run, a: BLSF2, b: BLSF2):
            assume(b != BLSF2.zero())
            assert cairo_run("blsf2_div", a, b) == a / b

        @given(a=...)
        def test_blsf2_div_by_zero_should_fail(self, cairo_run, a: BLSF2):
            b = BLSF2.zero()
            with strict_raises(AssertionError):
                cairo_run("blsf2_div", a, b)

        @given(a=..., b=...)
        @pytest.mark.slow
        def test_blsf2_div_patch_hint_should_fail(
            self, cairo_programs, cairo_run_py, a: BLSF2, b: BLSF2
        ):
            assume(b != BLSF2.zero())
            with patch_hint(
                cairo_programs,
                "blsf2_multiplicative_inverse",
                """
from cairo_addons.utils.uint384 import int_to_uint384

blsf2_struct_ptr = segments.add(2)
b_inv_c0_ptr = segments.gen_arg(int_to_uint384(0))
b_inv_c1_ptr = segments.gen_arg(int_to_uint384(0))
segments.load_data(blsf2_struct_ptr, [b_inv_c0_ptr, b_inv_c1_ptr])
segments.load_data(ids.b_inv.address_, [blsf2_struct_ptr])
                """,
            ), strict_raises(AssertionError):
                cairo_run_py("blsf2_div", a, b)

    class TestBLSP:
        @given(p=...)
        def test_blsp_init(self, cairo_run, p: Optimized_Point3D[BLSF]):
            assert cairo_run("blsp_init", p[0], p[1]) == p

        @given(x=..., y=...)
        def test_blsp_init_fails(self, cairo_run, x: BLSF, y: BLSF):
            with strict_raises(RuntimeError):
                cairo_run("blsp_init", x, y)

        def test_blsp_point_at_infinity(self, cairo_run):
            assert cairo_run("blsp_point_at_infinity") == Z1

        @given(a=..., b=...)
        def test_blsp_eq(
            self, cairo_run, a: Optimized_Point3D[BLSF], b: Optimized_Point3D[BLSF]
        ):
            # Python to Cairo -> a.normalize(), b.normalize()
            # Cairo to python ?? -> add a z = 1
            assert cairo_run("BLSP__eq__", a, b) == eq(a, b)

        @given(p=..., q=...)
        def test_blsp_add(
            self, cairo_run, p: Optimized_Point3D[BLSF], q: Optimized_Point3D[BLSF]
        ):
            assert cairo_run("blsp_add", p, q) == normalize1(add(p, q))

        @given(p=...)
        def test_blsp_double(self, cairo_run, p: Optimized_Point3D[BLSF]):
            assert cairo_run("blsp_double", p) == normalize1(double(p))

        @given(p=..., n=...)
        def test_blsp_mul_by(self, cairo_run, p: Optimized_Point3D[BLSF], n: U384):
            expected = multiply(p, int(n))
            if not is_inf(expected):
                expected = normalize1(expected)
            assert cairo_run("blsp_mul_by", p, n) == expected

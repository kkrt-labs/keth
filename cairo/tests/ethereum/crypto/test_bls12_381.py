from hypothesis import given
from py_ecc.fields import optimized_bls12_381_FQ as BLSF
from py_ecc.fields import optimized_bls12_381_FQ2 as BLSF2

# from py_ecc.optimized_bls12_381.optimized_curve import curve_order, field_modulus


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

    class TestBLSF2:
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
        def test_blsf2_eq(self, cairo_run, a: BLSF2, b: BLSF2):
            assert cairo_run("BLSF2__eq__", a, b) == (a == b)

        def test_BLSF2_ZERO(self, cairo_run):
            assert cairo_run("BLSF2_ZERO") == BLSF2.zero()

        def test_BLSF2_ONE(self, cairo_run):
            assert cairo_run("BLSF2_ONE") == BLSF2.one()

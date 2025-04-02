import pytest
from garaga.definitions import CurveID
from py_ecc.optimized_bls12_381.optimized_curve import (
    b,
    curve_order,
    field_modulus,
)


class TestBls12381:

    class TestConstants:
        def test_get_CURVE_ID(self, cairo_run):
            assert cairo_run("test__get_CURVE_ID") == CurveID.from_str("bls12381").value

        def test_get_P(self, cairo_run):
            assert cairo_run("test__get_P") == field_modulus

        def test_get_N(self, cairo_run):
            assert cairo_run("test__get_N") == curve_order

        def test_get_N_256(self, cairo_run):
            assert cairo_run("test__get_N_256") == curve_order

        def test_get_A(self, cairo_run):
            assert cairo_run("test__get_A") == 0

        def test_get_B(self, cairo_run):
            assert cairo_run("test__get_B") == b

        def test_get_G(self, cairo_run):
            assert cairo_run("test__get_G") == 3

        def test_get_P_MIN_ONE(self, cairo_run):
            assert cairo_run("test__get_P_MIN_ONE") == field_modulus - 1

        @pytest.mark.parametrize(
            "sign, expected",
            [
                (-1, field_modulus - 1),
                (1, 1),
            ],
        )
        def test_sign_to_uint384_mod_alt_bn128(self, cairo_run, sign, expected):
            res = cairo_run(
                "test__sign_to_uint384_mod_bls12_381",
                sign=sign,
            )

            assert res == expected

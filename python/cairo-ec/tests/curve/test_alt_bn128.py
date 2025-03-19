import pytest
from ethereum.crypto.alt_bn128 import ALT_BN128_CURVE_ORDER as AltBn128N
from ethereum.crypto.alt_bn128 import BNF as AltBn128P
from ethereum.crypto.alt_bn128 import BNP as AltBn128


class TestAltBn128:

    class TestConstants:
        def test_get_P(self, cairo_run):
            assert cairo_run("test__get_P") == AltBn128P.PRIME

        def test_get_P_256(self, cairo_run):
            assert cairo_run("test__get_P_256") == AltBn128P.PRIME

        def test_get_N(self, cairo_run):
            assert cairo_run("test__get_N") == AltBn128N

        def test_get_N_256(self, cairo_run):
            assert cairo_run("test__get_N_256") == AltBn128N

        def test_get_A(self, cairo_run):
            assert cairo_run("test__get_A") == AltBn128.A

        def test_get_B(self, cairo_run):
            assert cairo_run("test__get_B") == AltBn128.B

        def test_get_G(self, cairo_run):
            assert cairo_run("test__get_G") == 3

        def test_get_P_MIN_ONE(self, cairo_run):
            assert cairo_run("test__get_P_MIN_ONE") == AltBn128P.PRIME - 1

        @pytest.mark.parametrize(
            "sign, expected",
            [
                (-1, AltBn128P.PRIME - 1),
                (1, 1),
            ],
        )
        def test_sign_to_uint384_mod_alt_bn128(self, cairo_run, sign, expected):
            res = cairo_run(
                "test__sign_to_uint384_mod_alt_bn128",
                sign=sign,
            )

            assert res == expected

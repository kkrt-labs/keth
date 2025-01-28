import pytest

from cairo_addons.utils.uint256 import uint256_to_int
from cairo_addons.utils.uint384 import uint384_to_int
from ethereum.crypto.elliptic_curve import SECP256K1N, EllipticCurve
from ethereum.crypto.finite_field import PrimeField

pytestmark = pytest.mark.python_vm


class Secp256k1P(PrimeField):
    PRIME = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F


class Secp256k1(EllipticCurve):
    FIELD = Secp256k1P
    A = Secp256k1P(0)
    B = Secp256k1P(7)


class TestSecp256k1:

    class TestConstants:
        def test_get_P(self, cairo_run):
            assert (
                uint384_to_int(*cairo_run("test__get_P").values()) == Secp256k1P.PRIME
            )

        def test_get_P_256(self, cairo_run):
            assert (
                uint256_to_int(*cairo_run("test__get_P_256").values())
                == Secp256k1P.PRIME
            )

        def test_get_N(self, cairo_run):
            assert uint384_to_int(*cairo_run("test__get_N").values()) == int(SECP256K1N)

        def test_get_N_256(self, cairo_run):
            assert uint256_to_int(*cairo_run("test__get_N_256").values()) == int(
                SECP256K1N
            )

        def test_get_A(self, cairo_run):
            assert uint384_to_int(*cairo_run("test__get_A").values()) == Secp256k1.A

        def test_get_B(self, cairo_run):
            assert uint384_to_int(*cairo_run("test__get_B").values()) == Secp256k1.B

        def test_get_G(self, cairo_run):
            assert uint384_to_int(*cairo_run("test__get_G").values()) == 3

        def test_get_P_MIN_ONE(self, cairo_run):
            assert (
                uint384_to_int(*cairo_run("test__get_P_MIN_ONE").values())
                == Secp256k1P.PRIME - 1
            )

    class TestGetGeneratorPoint:
        def test_get_generator_point(self, cairo_run):
            cairo_run("test__get_generator_point")

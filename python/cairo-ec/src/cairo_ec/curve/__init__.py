"""
Just the EELS library with some modifications to make it easier to use in tests.
"""

from random import randint
from typing import Union

from ethereum.crypto.alt_bn128 import BNF as AltBn128P
from ethereum.crypto.elliptic_curve import EllipticCurve, F
from ethereum.crypto.finite_field import PrimeField
from sympy import sqrt_mod


class ECBase(EllipticCurve):

    A: PrimeField
    B: PrimeField
    G: PrimeField

    def __init__(self, x: Union[int, F], y: Union[int, F]):
        """
        Just making sure that coordinates are Field instances.
        """
        super().__init__(self.FIELD(x), self.FIELD(y))

    @classmethod
    def random_point(cls, x=None, retry=True) -> "EllipticCurve":
        """Generate a random point.

        If retry is True, the returned point is guaranteed to be on the curve.
        Otherwise, it just returns the first point it finds, which might not be on the curve.

        Uses try-and-increment method:
        1. Pick random x
        2. Compute x³ + ax + b
        3. If it's a quadratic residue, compute y
        4. If not, and retry is True, try another x
        5. If not, and retry is False, return (x, sqrt(x³ + ax + b) * g)
        """
        while True:
            # Random x in the field
            if x is None:
                x = cls.FIELD(randint(0, cls.FIELD.PRIME - 1))
            else:
                x = cls.FIELD(x)

            # Calculate right hand side: x³ + ax + b
            rhs = x**3 + cls.A * x + cls.B

            # Try to find square root
            y = sqrt_mod(rhs, cls.FIELD.PRIME)
            if isinstance(y, int):
                # Randomly choose between y and -y
                if randint(0, 1):
                    y = -y
                return cls.__new__(cls, cls.FIELD(x), cls.FIELD(y))
            if not retry:
                y = sqrt_mod(rhs * cls.G, cls.FIELD.PRIME)
                return cls.__new__(cls, cls.FIELD(x), cls.FIELD(y))

            x = cls.G * x

    @classmethod
    def is_on_curve(cls, x: int, y: int) -> bool:
        """Check if a point is on the curve."""
        y = cls.FIELD(y)
        x = cls.FIELD(x)
        return y**2 == x**3 + cls.A * x + cls.B


class Secp256k1P(PrimeField):
    PRIME = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F


class Secp256k1(ECBase):
    FIELD = Secp256k1P
    A = Secp256k1P(0)
    B = Secp256k1P(7)
    G = Secp256k1P(3)


class AltBn128(ECBase):
    FIELD = AltBn128P
    A = AltBn128P(0)
    B = AltBn128P(3)
    G = AltBn128P(3)

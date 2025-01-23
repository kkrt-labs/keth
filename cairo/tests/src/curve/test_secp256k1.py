import hypothesis.strategies as st
import pytest
from hypothesis import given
from sympy import sqrt_mod

from ethereum.crypto.elliptic_curve import EllipticCurve
from ethereum.crypto.finite_field import PrimeField
from src.utils.uint384 import int_to_uint384, uint384_to_int
from tests.utils.strategies import felt

pytestmark = pytest.mark.python_vm


class Secp256k1P(PrimeField):
    PRIME = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F


class Secp256k1(EllipticCurve):
    FIELD = Secp256k1P
    A = Secp256k1P(0)
    B = Secp256k1P(7)


uint384 = st.integers(min_value=0, max_value=2**384 - 1)


class TestSecp256k1:

    class TestGetGeneratorPoint:
        def test_get_generator_point(self, cairo_run):
            cairo_run("test__get_generator_point")

    class TestTryGetPointFromX:
        @given(x=uint384, v=felt)
        def test_try_get_point_from_x(self, cairo_run, x, v):
            y_try, is_on_curve = cairo_run(
                "test__try_get_point_from_x",
                x=int_to_uint384(x % Secp256k1.FIELD.PRIME),
                v=v,
            )

            square_root = sqrt_mod(
                x**3 + Secp256k1.A * x + Secp256k1.B, Secp256k1.FIELD.PRIME
            )
            assert (square_root is not None) == is_on_curve
            if square_root is not None:
                assert (
                    square_root
                    if (v % 2 == square_root % 2)
                    else (-square_root % Secp256k1.FIELD.PRIME)
                ) == uint384_to_int(y_try["d0"], y_try["d1"], y_try["d2"], y_try["d3"])

    class TestGetRandomPoint:
        @given(seed=felt)
        def test_should_return_a_point_on_the_curve(self, cairo_run, seed):
            point = cairo_run("test__get_random_point", seed=seed)
            x = uint384_to_int(
                point["x"]["d0"],
                point["x"]["d1"],
                point["x"]["d2"],
                point["x"]["d3"],
            )
            y = uint384_to_int(
                point["y"]["d0"],
                point["y"]["d1"],
                point["y"]["d2"],
                point["y"]["d3"],
            )
            assert (
                x**3 + Secp256k1.A * x + Secp256k1.B
            ) % Secp256k1.FIELD.PRIME == y**2 % Secp256k1.FIELD.PRIME

    class TestEcDouble:
        @given(seed=felt)
        def test_ec_double(self, cairo_run, seed):
            point = cairo_run("test__get_random_point", seed=seed)
            x = Secp256k1P(
                uint384_to_int(
                    point["x"]["d0"],
                    point["x"]["d1"],
                    point["x"]["d2"],
                    point["x"]["d3"],
                )
            )
            y = Secp256k1P(
                uint384_to_int(
                    point["y"]["d0"],
                    point["y"]["d1"],
                    point["y"]["d2"],
                    point["y"]["d3"],
                )
            )
            double = cairo_run(
                "test__ec_double",
                p=(
                    point["x"]["d0"],
                    point["x"]["d1"],
                    point["x"]["d2"],
                    point["x"]["d3"],
                    point["y"]["d0"],
                    point["y"]["d1"],
                    point["y"]["d2"],
                    point["y"]["d3"],
                ),
            )
            assert Secp256k1(x, y).double() == Secp256k1(
                uint384_to_int(
                    double["x"]["d0"],
                    double["x"]["d1"],
                    double["x"]["d2"],
                    double["x"]["d3"],
                ),
                uint384_to_int(
                    double["y"]["d0"],
                    double["y"]["d1"],
                    double["y"]["d2"],
                    double["y"]["d3"],
                ),
            )

    class TestEcAdd:
        @given(seed=felt)
        def test_ec_add(self, cairo_run, seed):
            p = cairo_run("test__get_random_point", seed=seed)
            q = cairo_run("test__get_random_point", seed=p["x"]["d0"])
            res = cairo_run(
                "test__ec_add",
                p=(
                    p["x"]["d0"],
                    p["x"]["d1"],
                    p["x"]["d2"],
                    p["x"]["d3"],
                    p["y"]["d0"],
                    p["y"]["d1"],
                    p["y"]["d2"],
                    p["y"]["d3"],
                ),
                q=(
                    q["x"]["d0"],
                    q["x"]["d1"],
                    q["x"]["d2"],
                    q["x"]["d3"],
                    q["y"]["d0"],
                    q["y"]["d1"],
                    q["y"]["d2"],
                    q["y"]["d3"],
                ),
            )
            assert Secp256k1(
                Secp256k1P(
                    uint384_to_int(
                        p["x"]["d0"], p["x"]["d1"], p["x"]["d2"], p["x"]["d3"]
                    )
                ),
                Secp256k1P(
                    uint384_to_int(
                        p["y"]["d0"], p["y"]["d1"], p["y"]["d2"], p["y"]["d3"]
                    )
                ),
            ) + (
                Secp256k1(
                    Secp256k1P(
                        uint384_to_int(
                            q["x"]["d0"], q["x"]["d1"], q["x"]["d2"], q["x"]["d3"]
                        )
                    ),
                    Secp256k1P(
                        uint384_to_int(
                            q["y"]["d0"], q["y"]["d1"], q["y"]["d2"], q["y"]["d3"]
                        )
                    ),
                )
            ) == Secp256k1(
                uint384_to_int(
                    res["x"]["d0"], res["x"]["d1"], res["x"]["d2"], res["x"]["d3"]
                ),
                uint384_to_int(
                    res["y"]["d0"], res["y"]["d1"], res["y"]["d2"], res["y"]["d3"]
                ),
            )

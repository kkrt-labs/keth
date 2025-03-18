import hypothesis.strategies as st
from hypothesis import given
from sympy import sqrt_mod

from cairo_addons.testing.strategies import felt
from cairo_addons.utils.uint384 import int_to_uint384, uint384_to_int
from cairo_ec.curve import AltBn128, Secp256k1
from tests.utils.args_gen import U384
from tests.utils.strategies import uint384

curve = st.one_of(st.just(Secp256k1), st.just(AltBn128))


class TestEcOps:

    class TestTryGetPointFromX:
        @given(x=..., v=felt, curve=curve)
        def test_try_get_point_from_x(self, cairo_run, x: U384, v, curve):
            y_try, is_on_curve = cairo_run(
                "test__try_get_point_from_x",
                x=x % U384(curve.FIELD.PRIME),
                v=v,
                a=U384(curve.A),
                b=U384(curve.B),
                g=U384(curve.G),
                p=U384(curve.FIELD.PRIME),
            )

            square_root = sqrt_mod(
                int(x) ** 3 + curve.A * int(x) + curve.B, curve.FIELD.PRIME
            )
            assert (square_root is not None) == is_on_curve
            if square_root is not None:
                assert (
                    square_root
                    if (v % 2 == square_root % 2)
                    else (-square_root % curve.FIELD.PRIME)
                ) == y_try

    class TestGetRandomPoint:
        # TODO: refactoring this requires more refactor on the G1Point struct definition and use.
        @given(seed=felt, curve=curve)
        def test_should_return_a_point_on_the_curve(self, cairo_run_py, seed, curve):
            point = cairo_run_py(
                "test__get_random_point",
                seed=seed,
                a=int_to_uint384(int(curve.A)),
                b=int_to_uint384(int(curve.B)),
                g=int_to_uint384(int(curve.G)),
                p=int_to_uint384(int(curve.FIELD.PRIME)),
            )
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
                x**3 + curve.A * x + curve.B
            ) % curve.FIELD.PRIME == y**2 % curve.FIELD.PRIME

    class TestEcAdd:
        @given(curve=curve)
        def test_ec_add(self, cairo_run, curve):
            p = curve.random_point()
            q = curve.random_point()
            res = cairo_run(
                "test__ec_add",
                p=[*int_to_uint384(int(p.x)), *int_to_uint384(int(p.y))],
                q=[*int_to_uint384(int(q.x)), *int_to_uint384(int(q.y))],
                a=int_to_uint384(int(curve.A)),
                modulus=int_to_uint384(int(curve.FIELD.PRIME)),
            )
            assert p + q == curve(
                *[curve.FIELD(uint384_to_int(**i)) for i in res.values()]
            )

        @given(curve=curve)
        def test_ec_add_equal(self, cairo_run, curve):
            p = curve.random_point()
            q = curve(p.x, p.y)
            res = cairo_run(
                "test__ec_add",
                p=[*int_to_uint384(int(p.x)), *int_to_uint384(int(p.y))],
                q=[*int_to_uint384(int(q.x)), *int_to_uint384(int(q.y))],
                a=int_to_uint384(int(curve.A)),
                modulus=int_to_uint384(int(curve.FIELD.PRIME)),
            )
            assert p + q == curve(
                *[curve.FIELD(uint384_to_int(**i)) for i in res.values()]
            )

        @given(curve=curve)
        def test_ec_add_opposite(self, cairo_run, curve):
            p = curve.random_point()
            q = curve(p.x, -p.y)
            res = cairo_run(
                "test__ec_add",
                p=[*int_to_uint384(int(p.x)), *int_to_uint384(int(p.y))],
                q=[*int_to_uint384(int(q.x)), *int_to_uint384(int(q.y))],
                a=int_to_uint384(int(curve.A)),
                modulus=int_to_uint384(int(curve.FIELD.PRIME)),
            )
            assert p + q == curve(
                *[curve.FIELD(uint384_to_int(**i)) for i in res.values()]
            )

        @given(
            curve=curve,
            scenario=st.sampled_from(
                [
                    "on_curve_plus_infinity",
                    "infinity_plus_on_curve",
                    "infinity_plus_infinity",
                ]
            ),
        )
        def test_ec_add_with_point_at_infinity(self, cairo_run, curve, scenario):
            p = curve.random_point()

            if scenario == "on_curve_plus_infinity":
                p1, p2 = [*int_to_uint384(int(p.x)), *int_to_uint384(int(p.y))], [
                    *int_to_uint384(int(0)),
                    *int_to_uint384(int(0)),
                ]
                expected = p
            elif scenario == "infinity_plus_on_curve":
                p1, p2 = [*int_to_uint384(int(0)), *int_to_uint384(int(0))], [
                    *int_to_uint384(int(p.x)),
                    *int_to_uint384(int(p.y)),
                ]
                expected = p
            else:
                p1, p2 = [*int_to_uint384(int(0)), *int_to_uint384(int(0))], [
                    *int_to_uint384(int(0)),
                    *int_to_uint384(int(0)),
                ]
                expected = curve(curve.FIELD(0), curve.FIELD(0))

            res = cairo_run(
                "test__ec_add",
                p=p1,
                q=p2,
                a=int_to_uint384(int(curve.A)),
                modulus=int_to_uint384(int(curve.FIELD.PRIME)),
            )

            result = curve(*[curve.FIELD(uint384_to_int(**i)) for i in res.values()])

            assert result == expected

    class TestEcMul:
        @given(data=st.data())
        def test_ec_mul(self, cairo_run, data):
            p = AltBn128.random_point()
            k = int(data.draw(uint384))
            expected = p.mul_by(k)
            res = cairo_run(
                "test__ec_mul",
                p=[*int_to_uint384(int(p.x)), *int_to_uint384(int(p.y))],
                k=int_to_uint384(k),
                modulus=int_to_uint384(int(AltBn128.FIELD.PRIME)),
            )
            res_point = AltBn128(
                *[AltBn128.FIELD(uint384_to_int(**i)) for i in res.values()]
            )
            assert expected == res_point

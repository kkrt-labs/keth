from typing import Type

import pytest
from ethereum.crypto.finite_field import PrimeField
from garaga.definitions import CurveID, G1Point
from garaga.hints.neg_3 import scalar_to_base_neg3_le
from garaga.starknet.tests_and_calldata_generators.msm import MSMCalldataBuilder
from hypothesis import Verbosity, assume, given, settings
from hypothesis import strategies as st
from sympy import sqrt_mod
from sympy.core.numbers import mod_inverse

from cairo_addons.testing.utils import flatten
from cairo_addons.utils.uint384 import int_to_uint384, uint384_to_int
from cairo_ec.compiler import circuit_compile
from cairo_ec.curve import ECBase


@pytest.fixture(scope="module")
def prime(request):
    return request.config.getoption("prime")


@pytest.fixture(scope="module")
def st_prime(prime):
    return st.integers(min_value=0, max_value=prime - 1)


@pytest.fixture(scope="module")
def prime_cls(prime):
    class Prime(PrimeField):
        PRIME = prime

    return Prime


@pytest.fixture(scope="module")
def curve(prime_cls: Type[PrimeField]):
    """
    Parameters from Secp256k1 curve but with the prime field from the fixture.
    """

    class Curve(ECBase):
        FIELD = prime_cls
        A = prime_cls(0)
        B = prime_cls(7)
        G = prime_cls(3)

    return Curve


class TestCircuits:
    class TestModOps:
        @given(data=st.data())
        @settings(verbosity=Verbosity.quiet)
        def test_add(self, cairo_program, cairo_run, prime_cls, st_prime, data):
            inputs = {"x": data.draw(st_prime), "y": data.draw(st_prime)}
            values_ptr = [limb for v in inputs.values() for limb in int_to_uint384(v)]
            compiled_circuit = circuit_compile(cairo_program, "add")

            expected_output = prime_cls(inputs["x"]) + prime_cls(inputs["y"])
            cairo_output = prime_cls(cairo_run("add", **inputs))
            circuit_output = prime_cls(
                uint384_to_int(
                    *cairo_run(
                        "test__circuit",
                        values_ptr=values_ptr,
                        values_ptr_len=len(values_ptr),
                        p=int_to_uint384(prime_cls.PRIME),
                        **compiled_circuit,
                    )[-compiled_circuit["return_data_size"] :]
                )
            )
            compiled_circuit_output = prime_cls(
                uint384_to_int(
                    **cairo_run(
                        "add_compiled",
                        **{k: int_to_uint384(v) for k, v in inputs.items()},
                        p=int_to_uint384(prime_cls.PRIME),
                    )
                )
            )
            assert (
                cairo_output
                == circuit_output
                == compiled_circuit_output
                == expected_output
            )

        @given(data=st.data())
        @settings(verbosity=Verbosity.quiet)
        def test_sub(self, cairo_program, cairo_run, prime_cls, st_prime, data):
            inputs = {"x": data.draw(st_prime), "y": data.draw(st_prime)}
            values_ptr = [limb for v in inputs.values() for limb in int_to_uint384(v)]
            compiled_circuit = circuit_compile(cairo_program, "sub")

            expected_output = prime_cls(inputs["x"]) - prime_cls(inputs["y"])
            cairo_output = prime_cls(cairo_run("sub", **inputs))
            circuit_output = prime_cls(
                uint384_to_int(
                    *cairo_run(
                        "test__circuit",
                        values_ptr=values_ptr,
                        values_ptr_len=len(values_ptr),
                        p=int_to_uint384(prime_cls.PRIME),
                        **compiled_circuit,
                    )[-compiled_circuit["return_data_size"] :]
                )
            )
            compiled_circuit_output = prime_cls(
                uint384_to_int(
                    **cairo_run(
                        "sub_compiled",
                        **{k: int_to_uint384(v) for k, v in inputs.items()},
                        p=int_to_uint384(prime_cls.PRIME),
                    )
                )
            )
            assert (
                cairo_output
                == circuit_output
                == compiled_circuit_output
                == expected_output
            )

        @given(data=st.data())
        @settings(verbosity=Verbosity.quiet)
        def test_mul(self, cairo_program, cairo_run, prime_cls, st_prime, data):
            inputs = {"x": data.draw(st_prime), "y": data.draw(st_prime)}
            values_ptr = [limb for v in inputs.values() for limb in int_to_uint384(v)]
            compiled_circuit = circuit_compile(cairo_program, "mul")

            expected_output = prime_cls(inputs["x"]) * prime_cls(inputs["y"])
            cairo_output = prime_cls(cairo_run("mul", **inputs))
            circuit_output = prime_cls(
                uint384_to_int(
                    *cairo_run(
                        "test__circuit",
                        values_ptr=values_ptr,
                        values_ptr_len=len(values_ptr),
                        p=int_to_uint384(prime_cls.PRIME),
                        **compiled_circuit,
                    )[-compiled_circuit["return_data_size"] :]
                )
            )
            compiled_circuit_output = prime_cls(
                uint384_to_int(
                    **cairo_run(
                        "mul_compiled",
                        **{k: int_to_uint384(v) for k, v in inputs.items()},
                        p=int_to_uint384(prime_cls.PRIME),
                    )
                )
            )
            assert (
                cairo_output
                == circuit_output
                == compiled_circuit_output
                == expected_output
            )

        @given(data=st.data())
        @settings(verbosity=Verbosity.quiet)
        def test_div(self, cairo_program, cairo_run, prime, data, prime_cls):
            inputs = {
                "x": data.draw(st.integers(min_value=0, max_value=prime - 1)),
                "y": data.draw(st.integers(min_value=1, max_value=prime - 1)),
            }
            values_ptr = [limb for v in inputs.values() for limb in int_to_uint384(v)]
            compiled_circuit = circuit_compile(cairo_program, "div")

            expected_output = prime_cls(inputs["x"]) * prime_cls(
                mod_inverse(prime_cls(inputs["y"]), prime_cls.PRIME)
            )
            cairo_output = prime_cls(cairo_run("div", **inputs))
            circuit_output = prime_cls(
                uint384_to_int(
                    *cairo_run(
                        "test__circuit",
                        values_ptr=values_ptr,
                        values_ptr_len=len(values_ptr),
                        p=int_to_uint384(prime_cls.PRIME),
                        **compiled_circuit,
                    )[-compiled_circuit["return_data_size"] :]
                )
            )
            compiled_circuit_output = prime_cls(
                uint384_to_int(
                    **cairo_run(
                        "div_compiled",
                        **{k: int_to_uint384(v) for k, v in inputs.items()},
                        p=int_to_uint384(prime_cls.PRIME),
                    )
                )
            )
            assert (
                cairo_output
                == circuit_output
                == compiled_circuit_output
                == expected_output
            )

        @given(data=st.data())
        @settings(verbosity=Verbosity.quiet)
        def test_diff_ratio(self, cairo_program, cairo_run, prime_cls, st_prime, data):
            inputs = {"x": data.draw(st_prime), "y": data.draw(st_prime)}
            assume(inputs["x"] != inputs["y"])
            values_ptr = [limb for v in inputs.values() for limb in int_to_uint384(v)]
            compiled_circuit = circuit_compile(cairo_program, "diff_ratio")

            expected_output = prime_cls(
                (inputs["x"] - inputs["y"])
                * mod_inverse(inputs["x"] - inputs["y"], prime_cls.PRIME)
            )
            cairo_output = prime_cls(cairo_run("diff_ratio", **inputs))
            circuit_output = prime_cls(
                uint384_to_int(
                    *cairo_run(
                        "test__circuit",
                        values_ptr=values_ptr,
                        values_ptr_len=len(values_ptr),
                        p=int_to_uint384(prime_cls.PRIME),
                        **compiled_circuit,
                    )[-compiled_circuit["return_data_size"] :]
                )
            )
            compiled_circuit_output = prime_cls(
                uint384_to_int(
                    **cairo_run(
                        "diff_ratio_compiled",
                        **{k: int_to_uint384(v) for k, v in inputs.items()},
                        p=int_to_uint384(prime_cls.PRIME),
                    )
                )
            )
            assert (
                cairo_output
                == circuit_output
                == compiled_circuit_output
                == expected_output
            )

        @given(data=st.data())
        @settings(verbosity=Verbosity.quiet)
        def test_sum_ratio(self, cairo_program, cairo_run, prime_cls, st_prime, data):
            inputs = {"x": data.draw(st_prime), "y": data.draw(st_prime)}
            assume(inputs["x"] != -inputs["y"])
            values_ptr = [limb for v in inputs.values() for limb in int_to_uint384(v)]
            compiled_circuit = circuit_compile(cairo_program, "sum_ratio")

            expected_output = prime_cls(
                (inputs["x"] + inputs["y"])
                * mod_inverse(inputs["x"] + inputs["y"], prime_cls.PRIME)
            )
            cairo_output = prime_cls(cairo_run("sum_ratio", **inputs))
            circuit_output = prime_cls(
                uint384_to_int(
                    *cairo_run(
                        "test__circuit",
                        values_ptr=values_ptr,
                        values_ptr_len=len(values_ptr),
                        p=int_to_uint384(prime_cls.PRIME),
                        **compiled_circuit,
                    )[-compiled_circuit["return_data_size"] :]
                )
            )
            compiled_circuit_output = prime_cls(
                uint384_to_int(
                    **cairo_run(
                        "sum_ratio_compiled",
                        **{k: int_to_uint384(v) for k, v in inputs.items()},
                        p=int_to_uint384(prime_cls.PRIME),
                    )
                )
            )
            assert (
                cairo_output
                == circuit_output
                == compiled_circuit_output
                == expected_output
            )

        @given(data=st.data())
        @settings(verbosity=Verbosity.quiet)
        def test_inv(self, cairo_program, cairo_run, prime, data, prime_cls):
            inputs = {
                "x": data.draw(st.integers(min_value=1, max_value=prime - 1)),
            }
            compiled_circuit = circuit_compile(cairo_program, "inv")
            values_ptr = flatten(
                compiled_circuit["constants"]
                + [limb for v in inputs.values() for limb in int_to_uint384(v)]
            )

            expected_output = prime_cls(mod_inverse(inputs["x"], prime_cls.PRIME))
            cairo_output = prime_cls(cairo_run("inv", **inputs))
            circuit_output = prime_cls(
                uint384_to_int(
                    *cairo_run(
                        "test__circuit",
                        values_ptr=values_ptr,
                        values_ptr_len=len(values_ptr),
                        p=int_to_uint384(prime_cls.PRIME),
                        **compiled_circuit,
                    )[-compiled_circuit["return_data_size"] :]
                )
            )
            compiled_circuit_output = prime_cls(
                uint384_to_int(
                    **cairo_run(
                        "inv_compiled",
                        **{k: int_to_uint384(v) for k, v in inputs.items()},
                        p=int_to_uint384(prime_cls.PRIME),
                    )
                )
            )
            assert (
                cairo_output
                == circuit_output
                == compiled_circuit_output
                == expected_output
            )

        @given(data=st.data())
        @settings(verbosity=Verbosity.quiet)
        def test_assert_is_quad_residue(
            self, cairo_program, cairo_run, curve, data, st_prime
        ):
            x = data.draw(st_prime)
            root = sqrt_mod(x, curve.FIELD.PRIME)
            is_quad_residue = root is not None
            root = root or sqrt_mod(x * curve.G, curve.FIELD.PRIME)
            inputs = {
                "x": x,
                "root": root,
                "g": int(curve.G),
                "is_quad_residue": is_quad_residue,
            }
            compiled_circuit = circuit_compile(cairo_program, "assert_is_quad_residue")
            values_ptr = flatten(compiled_circuit["constants"]) + [
                limb for v in inputs.values() for limb in int_to_uint384(v)
            ]

            cairo_run("assert_is_quad_residue", **inputs)
            cairo_run(
                "test__circuit",
                values_ptr=values_ptr,
                values_ptr_len=len(values_ptr),
                p=int_to_uint384(curve.FIELD.PRIME),
                **compiled_circuit,
            )
            cairo_run(
                "assert_is_quad_residue_compiled",
                **{k: int_to_uint384(v) for k, v in inputs.items()},
                p=int_to_uint384(curve.FIELD.PRIME),
            )

        @given(data=st.data())
        @settings(verbosity=Verbosity.quiet)
        def test_assert_eq(self, cairo_program, cairo_run, prime, prime_cls, data):
            value = data.draw(st.integers(min_value=0, max_value=prime - 1))
            inputs = {
                "x": value,
                "y": value,
            }
            compiled_circuit = circuit_compile(cairo_program, "assert_eq")
            values_ptr = flatten(compiled_circuit["constants"]) + [
                limb for v in inputs.values() for limb in int_to_uint384(v)
            ]

            cairo_run("assert_eq", **inputs)
            cairo_run(
                "test__circuit",
                values_ptr=values_ptr,
                values_ptr_len=len(values_ptr),
                p=int_to_uint384(prime_cls.PRIME),
                **compiled_circuit,
            )
            cairo_run(
                "assert_eq_compiled",
                **{k: int_to_uint384(v) for k, v in inputs.items()},
                p=int_to_uint384(prime_cls.PRIME),
            )

        @given(data=st.data())
        @settings(verbosity=Verbosity.quiet)
        def test_assert_neq(self, cairo_program, cairo_run, prime, prime_cls, data):
            inputs = {
                "x": data.draw(st.integers(min_value=0, max_value=prime - 1)),
                "y": data.draw(st.integers(min_value=0, max_value=prime - 1)),
            }
            assume(inputs["x"] != inputs["y"])
            compiled_circuit = circuit_compile(cairo_program, "assert_neq")
            values_ptr = flatten(compiled_circuit["constants"]) + [
                limb for v in inputs.values() for limb in int_to_uint384(v)
            ]

            cairo_run("assert_neq", **inputs)
            cairo_run(
                "test__circuit",
                values_ptr=values_ptr,
                values_ptr_len=len(values_ptr),
                p=int_to_uint384(prime_cls.PRIME),
                **compiled_circuit,
            )
            cairo_run(
                "assert_neq_compiled",
                **{k: int_to_uint384(v) for k, v in inputs.items()},
                p=int_to_uint384(prime_cls.PRIME),
            )

        @given(data=st.data())
        @settings(verbosity=Verbosity.quiet)
        def test_neg(self, cairo_program, cairo_run, prime_cls, st_prime, data):
            inputs = {"y": data.draw(st_prime)}
            values_ptr = [limb for v in inputs.values() for limb in int_to_uint384(v)]
            compiled_circuit = circuit_compile(cairo_program, "neg")
            values_ptr = flatten(compiled_circuit["constants"]) + [
                limb for v in inputs.values() for limb in int_to_uint384(v)
            ]

            expected_output = prime_cls(-inputs["y"])
            cairo_output = prime_cls(cairo_run("neg", **inputs))
            circuit_output = prime_cls(
                uint384_to_int(
                    *cairo_run(
                        "test__circuit",
                        values_ptr=values_ptr,
                        values_ptr_len=len(values_ptr),
                        p=int_to_uint384(prime_cls.PRIME),
                        **compiled_circuit,
                    )[-compiled_circuit["return_data_size"] :]
                )
            )
            compiled_circuit_output = prime_cls(
                uint384_to_int(
                    **cairo_run(
                        "neg_compiled",
                        **{k: int_to_uint384(v) for k, v in inputs.items()},
                        p=int_to_uint384(prime_cls.PRIME),
                    )
                )
            )
            assert (
                cairo_output
                == circuit_output
                == compiled_circuit_output
                == expected_output
            )

        @given(data=st.data())
        @settings(verbosity=Verbosity.quiet)
        def test_assert_neg(self, cairo_program, cairo_run, prime_cls, st_prime, data):
            y = data.draw(st_prime)
            x = prime_cls(-y)
            inputs = {"x": int(x), "y": y}
            compiled_circuit = circuit_compile(cairo_program, "assert_neg")
            values_ptr = flatten(compiled_circuit["constants"]) + [
                limb for v in inputs.values() for limb in int_to_uint384(v)
            ]

            # No return value, just checking that it doesn't fail
            cairo_run("assert_neg", **inputs)
            cairo_run(
                "test__circuit",
                values_ptr=values_ptr,
                values_ptr_len=len(values_ptr),
                p=int_to_uint384(prime_cls.PRIME),
                **compiled_circuit,
            )
            cairo_run(
                "assert_neg_compiled",
                **{k: int_to_uint384(v) for k, v in inputs.items()},
                p=int_to_uint384(prime_cls.PRIME),
            )

        @given(data=st.data())
        @settings(verbosity=Verbosity.quiet)
        def test_assert_not_neg(
            self, cairo_program, cairo_run, prime_cls, st_prime, data
        ):
            y = data.draw(st_prime)
            x = data.draw(st_prime)
            assume(x != prime_cls(-y))
            inputs = {"x": int(x), "y": y}
            compiled_circuit = circuit_compile(cairo_program, "assert_not_neg")
            values_ptr = flatten(compiled_circuit["constants"]) + [
                limb for v in inputs.values() for limb in int_to_uint384(v)
            ]

            # No return value, just checking that it doesn't fail
            cairo_run("assert_not_neg", **inputs)
            cairo_run(
                "test__circuit",
                values_ptr=values_ptr,
                values_ptr_len=len(values_ptr),
                p=int_to_uint384(prime_cls.PRIME),
                **compiled_circuit,
            )
            cairo_run(
                "assert_not_neg_compiled",
                **{k: int_to_uint384(v) for k, v in inputs.items()},
                p=int_to_uint384(prime_cls.PRIME),
            )

    class TestEcOps:
        @given(data=st.data())
        @settings(verbosity=Verbosity.quiet)
        def test_ec_add(self, cairo_program, cairo_run, curve, data, st_prime):
            seed_p = data.draw(st_prime)
            seed_q = data.draw(st_prime)
            assume(seed_p != seed_q)

            p = curve.random_point(x=seed_p)
            q = curve.random_point(x=seed_q)
            inputs = {"x0": int(p.x), "y0": int(p.y), "x1": int(q.x), "y1": int(q.y)}
            expected_output = p + q

            cairo_output = cairo_run("ec_add", **inputs)
            compiled_circuit = circuit_compile(cairo_program, "ec_add")
            values_ptr = flatten(compiled_circuit["constants"]) + [
                limb for v in inputs.values() for limb in int_to_uint384(v)
            ]
            r = cairo_run(
                "test__circuit",
                values_ptr=values_ptr,
                values_ptr_len=len(values_ptr),
                p=int_to_uint384(curve.FIELD.PRIME),
                **compiled_circuit,
            )[-compiled_circuit["return_data_size"] :]
            circuit_output = [
                uint384_to_int(*r[:4]) % curve.FIELD.PRIME,
                uint384_to_int(*r[4:]) % curve.FIELD.PRIME,
            ]
            compiled_circuit_output = [
                uint384_to_int(**coord) % curve.FIELD.PRIME
                for coord in cairo_run(
                    "ec_add_compiled",
                    **{k: int_to_uint384(v) for k, v in inputs.items()},
                    p=int_to_uint384(curve.FIELD.PRIME),
                )
            ]
            assert (
                cairo_output
                == circuit_output
                == compiled_circuit_output
                == [expected_output.x, expected_output.y]
            )

        @given(data=st.data())
        @settings(verbosity=Verbosity.quiet)
        def test_ec_double(self, cairo_program, cairo_run, curve, data, st_prime):
            seed_p = data.draw(st_prime)
            p = curve.random_point(x=seed_p)
            assume(p.y != 0)
            inputs = {"x0": int(p.x), "y0": int(p.y), "a": int(curve.A)}
            expected_output = p.double()

            cairo_output = cairo_run("ec_double", **inputs)
            compiled_circuit = circuit_compile(cairo_program, "ec_double")
            values_ptr = flatten(compiled_circuit["constants"]) + [
                limb for v in inputs.values() for limb in int_to_uint384(v)
            ]
            r = cairo_run(
                "test__circuit",
                values_ptr=values_ptr,
                values_ptr_len=len(values_ptr),
                p=int_to_uint384(curve.FIELD.PRIME),
                **compiled_circuit,
            )[-compiled_circuit["return_data_size"] :]
            circuit_output = [
                uint384_to_int(*r[:4]) % curve.FIELD.PRIME,
                uint384_to_int(*r[4:]) % curve.FIELD.PRIME,
            ]
            compiled_circuit_output = [
                uint384_to_int(**coord) % curve.FIELD.PRIME
                for coord in cairo_run(
                    "ec_double_compiled",
                    **{k: int_to_uint384(v) for k, v in inputs.items()},
                    p=int_to_uint384(curve.FIELD.PRIME),
                )
            ]
            assert (
                cairo_output
                == circuit_output
                == compiled_circuit_output
                == [expected_output.x, expected_output.y]
            )

        @given(data=st.data())
        @settings(verbosity=Verbosity.quiet)
        def test_assert_x_is_on_curve(
            self, cairo_program, cairo_run, curve, data, st_prime
        ):
            seed_p = data.draw(st_prime)
            p = curve.random_point(x=seed_p, retry=False)
            inputs = {
                "x": int(p.x),
                "y": int(p.y),
                "a": int(curve.A),
                "b": int(curve.B),
                "g": int(curve.G),
                "is_on_curve": curve.is_on_curve(p.x, p.y),
            }

            cairo_run("assert_x_is_on_curve", **inputs)
            compiled_circuit = circuit_compile(cairo_program, "assert_x_is_on_curve")
            values_ptr = flatten(compiled_circuit["constants"]) + [
                limb for v in inputs.values() for limb in int_to_uint384(v)
            ]
            cairo_run(
                "test__circuit",
                values_ptr=values_ptr,
                values_ptr_len=len(values_ptr),
                p=int_to_uint384(curve.FIELD.PRIME),
                **compiled_circuit,
            )
            cairo_run(
                "assert_x_is_on_curve_compiled",
                **{k: int_to_uint384(v) for k, v in inputs.items()},
                p=int_to_uint384(curve.FIELD.PRIME),
            )

        @given(data=st.data())
        @settings(verbosity=Verbosity.quiet)
        def test_assert_not_on_curve(
            self, cairo_program, cairo_run, curve, data, st_prime
        ):
            seed_p = data.draw(st_prime)
            p = curve.random_point(x=seed_p, retry=False)
            assume(not curve.is_on_curve(p.x, p.y))
            inputs = {
                "x": int(p.x),
                "y": int(p.y),
                "a": int(curve.A),
                "b": int(curve.B),
            }
            cairo_run("assert_not_on_curve", **inputs)
            compiled_circuit = circuit_compile(cairo_program, "assert_not_on_curve")
            values_ptr = flatten(compiled_circuit["constants"]) + [
                limb for v in inputs.values() for limb in int_to_uint384(v)
            ]
            cairo_run(
                "test__circuit",
                values_ptr=values_ptr,
                values_ptr_len=len(values_ptr),
                p=int_to_uint384(curve.FIELD.PRIME),
                **compiled_circuit,
            )
            cairo_run(
                "assert_not_on_curve_compiled",
                **{k: int_to_uint384(v) for k, v in inputs.items()},
                p=int_to_uint384(curve.FIELD.PRIME),
            )

        @given(data=st.data())
        @settings(verbosity=Verbosity.quiet)
        def test_assert_on_curve(self, cairo_program, cairo_run, curve, data, st_prime):
            seed_p = data.draw(st_prime)
            p = curve.random_point(x=seed_p, retry=True)
            inputs = {
                "x": int(p.x),
                "y": int(p.y),
                "a": int(curve.A),
                "b": int(curve.B),
            }

            cairo_run("assert_on_curve", **inputs)
            compiled_circuit = circuit_compile(cairo_program, "assert_on_curve")
            values_ptr = flatten(compiled_circuit["constants"]) + [
                limb for v in inputs.values() for limb in int_to_uint384(v)
            ]

            cairo_run(
                "test__circuit",
                values_ptr=values_ptr,
                values_ptr_len=len(values_ptr),
                p=int_to_uint384(curve.FIELD.PRIME),
                **compiled_circuit,
            )
            cairo_run(
                "assert_on_curve_compiled",
                **{k: int_to_uint384(v) for k, v in inputs.items()},
                p=int_to_uint384(curve.FIELD.PRIME),
            )

        @given(data=st.data())
        def test_ecip_2P(self, cairo_program, cairo_run, curve, data, st_prime):
            seed_g = data.draw(
                st.integers(min_value=1, max_value=curve.FIELD.PRIME - 1)
            )
            seed_r = data.draw(
                st.integers(min_value=1, max_value=curve.FIELD.PRIME - 1)
            )
            assume(seed_g != seed_r)
            g = curve.random_point(x=seed_g)
            r = curve.random_point(x=seed_r)
            points = [
                G1Point(g.x, g.y, CurveID.SECP256K1),
                G1Point(r.x, r.y, CurveID.SECP256K1),
            ]

            # n is the order of the SECP256K1 elliptic curve
            n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
            u1 = data.draw(st.integers(min_value=2**128 + 1, max_value=n))
            u2 = data.draw(st.integers(min_value=2**128 + 1, max_value=n))
            scalars = [u1, u2]

            builder = MSMCalldataBuilder(CurveID.SECP256K1, points, scalars)
            (msm_hint, _, a0, rlc_coeff) = builder.build_msm_hints()
            scalars_low, scalars_high = builder.scalars_split()
            epns_low, epns_high = [scalar_to_base_neg3_le(s) for s in scalars_low], [
                scalar_to_base_neg3_le(s) for s in scalars_high
            ]

            Q_low, Q_high, Q_high_shifted, RLCSumDlogDiv = msm_hint.elmts

            inputs = {
                "div_a_coeff_0": int(RLCSumDlogDiv.a_num[0].value),
                "div_a_coeff_1": int(RLCSumDlogDiv.a_num[1].value),
                "div_a_coeff_2": int(RLCSumDlogDiv.a_num[2].value),
                "div_a_coeff_3": int(RLCSumDlogDiv.a_num[3].value),
                "div_a_coeff_4": int(RLCSumDlogDiv.a_num[4].value),
                "div_b_coeff_0": int(RLCSumDlogDiv.a_den[0].value),
                "div_b_coeff_1": int(RLCSumDlogDiv.a_den[1].value),
                "div_b_coeff_2": int(RLCSumDlogDiv.a_den[2].value),
                "div_b_coeff_3": int(RLCSumDlogDiv.a_den[3].value),
                "div_b_coeff_4": int(RLCSumDlogDiv.a_den[4].value),
                "div_b_coeff_5": int(RLCSumDlogDiv.a_den[5].value),
                "div_c_coeff_0": int(RLCSumDlogDiv.b_num[0].value),
                "div_c_coeff_1": int(RLCSumDlogDiv.b_num[1].value),
                "div_c_coeff_2": int(RLCSumDlogDiv.b_num[2].value),
                "div_c_coeff_3": int(RLCSumDlogDiv.b_num[3].value),
                "div_c_coeff_4": int(RLCSumDlogDiv.b_num[4].value),
                "div_c_coeff_5": int(RLCSumDlogDiv.b_num[5].value),
                "div_d_coeff_0": int(RLCSumDlogDiv.b_den[0].value),
                "div_d_coeff_1": int(RLCSumDlogDiv.b_den[1].value),
                "div_d_coeff_2": int(RLCSumDlogDiv.b_den[2].value),
                "div_d_coeff_3": int(RLCSumDlogDiv.b_den[3].value),
                "div_d_coeff_4": int(RLCSumDlogDiv.b_den[4].value),
                "div_d_coeff_5": int(RLCSumDlogDiv.b_den[5].value),
                "div_d_coeff_6": int(RLCSumDlogDiv.b_den[6].value),
                "div_d_coeff_7": int(RLCSumDlogDiv.b_den[7].value),
                "div_d_coeff_8": int(RLCSumDlogDiv.b_den[8].value),
                "x_g": int(points[0].x),
                "y_g": int(points[0].y),
                "x_r": int(points[1].x),
                "y_r": int(points[1].y),
                "ep1_low": int(epns_low[0][0]),
                "en1_low": int(epns_low[0][1]),
                "sp1_low": int(epns_low[0][2] % curve.FIELD.PRIME),
                "sn1_low": int(epns_low[0][3] % curve.FIELD.PRIME),
                "ep2_low": int(epns_low[1][0]),
                "en2_low": int(epns_low[1][1]),
                "sp2_low": int(epns_low[1][2] % curve.FIELD.PRIME),
                "sn2_low": int(epns_low[1][3] % curve.FIELD.PRIME),
                "ep1_high": int(epns_high[0][0]),
                "en1_high": int(epns_high[0][1]),
                "sp1_high": int(epns_high[0][2] % curve.FIELD.PRIME),
                "sn1_high": int(epns_high[0][3] % curve.FIELD.PRIME),
                "ep2_high": int(epns_high[1][0]),
                "en2_high": int(epns_high[1][1]),
                "sp2_high": int(epns_high[1][2] % curve.FIELD.PRIME),
                "sn2_high": int(epns_high[1][3] % curve.FIELD.PRIME),
                "x_q_low": int(Q_low.elmts[0].value),
                "y_q_low": int(Q_low.elmts[1].value),
                "x_q_high": int(Q_high.elmts[0].value),
                "y_q_high": int(Q_high.elmts[1].value),
                "x_q_high_shifted": int(Q_high_shifted.elmts[0].value),
                "y_q_high_shifted": int(Q_high_shifted.elmts[1].value),
                "x_a0": int(a0.x),
                "y_a0": int(a0.y),
                "a": int(curve.A),
                "b": int(curve.B),
                "base_rlc": int(rlc_coeff),
            }

            cairo_run("ecip_2P", **inputs)

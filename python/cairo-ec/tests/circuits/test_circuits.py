from typing import Type

import pytest
from ethereum.crypto.finite_field import PrimeField
from garaga.algebra import FunctionFelt
from garaga.definitions import CURVES, CurveID, G1Point
from garaga.hints.ecip import derive_ec_point_from_X, zk_ecip_hint
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
        def test_ecip_2p(self, cairo_program, cairo_run, data, prime):
            curve_id = CurveID.from_str("secp256k1")
            curve = CURVES[curve_id.value]
            g = G1Point.gen_random_point(curve_id)
            r = G1Point.gen_random_point(curve_id)
            points = [g, r]

            u1 = data.draw(st.integers(min_value=2**128 + 1, max_value=curve.n))
            u2 = data.draw(st.integers(min_value=2**128 + 1, max_value=curve.n))
            scalars = [u1, u2]

            builder = MSMCalldataBuilder(curve_id, points, scalars)
            (q_low, q_high, q_high_shifted, rlc_sum_dlog_div, a0, rlc_coeff) = (
                build_msm_hints(msm=builder)
            )
            scalars_low, scalars_high = builder.scalars_split()
            epns_low, epns_high = [scalar_to_base_neg3_le(s) for s in scalars_low], [
                scalar_to_base_neg3_le(s) for s in scalars_high
            ]

            inputs = {
                "div_a_coeff_0": int(rlc_sum_dlog_div.a.numerator[0].value),
                "div_a_coeff_1": int(rlc_sum_dlog_div.a.numerator[1].value),
                "div_a_coeff_2": int(rlc_sum_dlog_div.a.numerator[2].value),
                "div_a_coeff_3": int(rlc_sum_dlog_div.a.numerator[3].value),
                "div_a_coeff_4": int(rlc_sum_dlog_div.a.numerator[4].value),
                "div_b_coeff_0": int(rlc_sum_dlog_div.a.denominator[0].value),
                "div_b_coeff_1": int(rlc_sum_dlog_div.a.denominator[1].value),
                "div_b_coeff_2": int(rlc_sum_dlog_div.a.denominator[2].value),
                "div_b_coeff_3": int(rlc_sum_dlog_div.a.denominator[3].value),
                "div_b_coeff_4": int(rlc_sum_dlog_div.a.denominator[4].value),
                "div_b_coeff_5": int(rlc_sum_dlog_div.a.denominator[5].value),
                "div_c_coeff_0": int(rlc_sum_dlog_div.b.numerator[0].value),
                "div_c_coeff_1": int(rlc_sum_dlog_div.b.numerator[1].value),
                "div_c_coeff_2": int(rlc_sum_dlog_div.b.numerator[2].value),
                "div_c_coeff_3": int(rlc_sum_dlog_div.b.numerator[3].value),
                "div_c_coeff_4": int(rlc_sum_dlog_div.b.numerator[4].value),
                "div_c_coeff_5": int(rlc_sum_dlog_div.b.numerator[5].value),
                "div_d_coeff_0": int(rlc_sum_dlog_div.b.denominator[0].value),
                "div_d_coeff_1": int(rlc_sum_dlog_div.b.denominator[1].value),
                "div_d_coeff_2": int(rlc_sum_dlog_div.b.denominator[2].value),
                "div_d_coeff_3": int(rlc_sum_dlog_div.b.denominator[3].value),
                "div_d_coeff_4": int(rlc_sum_dlog_div.b.denominator[4].value),
                "div_d_coeff_5": int(rlc_sum_dlog_div.b.denominator[5].value),
                "div_d_coeff_6": int(rlc_sum_dlog_div.b.denominator[6].value),
                "div_d_coeff_7": int(rlc_sum_dlog_div.b.denominator[7].value),
                "div_d_coeff_8": int(rlc_sum_dlog_div.b.denominator[8].value),
                "g_x": int(points[0].x),
                "g_y": int(points[0].y),
                "r_x": int(points[1].x),
                "r_y": int(points[1].y),
                "ep1_low": int(epns_low[0][0]),
                "en1_low": int(epns_low[0][1]),
                "sp1_low": int(epns_low[0][2] % curve.p),
                "sn1_low": int(epns_low[0][3] % curve.p),
                "ep2_low": int(epns_low[1][0]),
                "en2_low": int(epns_low[1][1]),
                "sp2_low": int(epns_low[1][2] % curve.p),
                "sn2_low": int(epns_low[1][3] % curve.p),
                "ep1_high": int(epns_high[0][0]),
                "en1_high": int(epns_high[0][1]),
                "sp1_high": int(epns_high[0][2] % curve.p),
                "sn1_high": int(epns_high[0][3] % curve.p),
                "ep2_high": int(epns_high[1][0]),
                "en2_high": int(epns_high[1][1]),
                "sp2_high": int(epns_high[1][2] % curve.p),
                "sn2_high": int(epns_high[1][3] % curve.p),
                "q_low_x": int(q_low.x),
                "q_low_y": int(q_low.y),
                "q_high_x": int(q_high.x),
                "q_high_y": int(q_high.y),
                "q_high_shifted_x": int(q_high_shifted.x),
                "q_high_shifted_y": int(q_high_shifted.y),
                "a0_x": int(a0.x),
                "a0_y": int(a0.y),
                "a": int(curve.a),
                "b": int(curve.b),
                "base_rlc": int(rlc_coeff),
            }

            if prime == curve.p:
                cairo_run("ecip_2p", **inputs)
            compiled_circuit = circuit_compile(cairo_program, "ecip_2p")
            values_ptr = flatten(compiled_circuit["constants"]) + [
                limb for v in inputs.values() for limb in int_to_uint384(v)
            ]
            cairo_run(
                "test__circuit",
                values_ptr=values_ptr,
                values_ptr_len=len(values_ptr),
                p=int_to_uint384(curve.p),
                **compiled_circuit,
            )
            cairo_run(
                "ecip_2p_compiled",
                **{k: int_to_uint384(v) for k, v in inputs.items()},
                p=int_to_uint384(curve.p),
            )

        @given(data=st.data())
        def test_ecip_1p(self, cairo_program, cairo_run, data, prime):
            curve_id = CurveID.from_str("secp256k1")
            curve = CURVES[curve_id.value]
            g = G1Point.gen_random_point(curve_id)
            points = [g]

            u1 = data.draw(st.integers(min_value=2**128 + 1, max_value=curve.n))
            scalars = [u1]

            builder = MSMCalldataBuilder(curve_id, points, scalars)
            (q_low, q_high, q_high_shifted, rlc_sum_dlog_div, a0, rlc_coeff) = (
                build_msm_hints(msm=builder)
            )
            scalars_low, scalars_high = builder.scalars_split()
            epns_low, epns_high = [scalar_to_base_neg3_le(s) for s in scalars_low], [
                scalar_to_base_neg3_le(s) for s in scalars_high
            ]

            inputs = {
                "div_a_coeff_0": int(rlc_sum_dlog_div.a.numerator[0].value),
                "div_a_coeff_1": int(rlc_sum_dlog_div.a.numerator[1].value),
                "div_a_coeff_2": int(rlc_sum_dlog_div.a.numerator[2].value),
                "div_a_coeff_3": int(rlc_sum_dlog_div.a.numerator[3].value),
                "div_b_coeff_0": int(rlc_sum_dlog_div.a.denominator[0].value),
                "div_b_coeff_1": int(rlc_sum_dlog_div.a.denominator[1].value),
                "div_b_coeff_2": int(rlc_sum_dlog_div.a.denominator[2].value),
                "div_b_coeff_3": int(rlc_sum_dlog_div.a.denominator[3].value),
                "div_b_coeff_4": int(rlc_sum_dlog_div.a.denominator[4].value),
                "div_c_coeff_0": int(rlc_sum_dlog_div.b.numerator[0].value),
                "div_c_coeff_1": int(rlc_sum_dlog_div.b.numerator[1].value),
                "div_c_coeff_2": int(rlc_sum_dlog_div.b.numerator[2].value),
                "div_c_coeff_3": int(rlc_sum_dlog_div.b.numerator[3].value),
                "div_c_coeff_4": int(rlc_sum_dlog_div.b.numerator[4].value),
                "div_d_coeff_0": int(rlc_sum_dlog_div.b.denominator[0].value),
                "div_d_coeff_1": int(rlc_sum_dlog_div.b.denominator[1].value),
                "div_d_coeff_2": int(rlc_sum_dlog_div.b.denominator[2].value),
                "div_d_coeff_3": int(rlc_sum_dlog_div.b.denominator[3].value),
                "div_d_coeff_4": int(rlc_sum_dlog_div.b.denominator[4].value),
                "div_d_coeff_5": int(rlc_sum_dlog_div.b.denominator[5].value),
                "div_d_coeff_6": int(rlc_sum_dlog_div.b.denominator[6].value),
                "div_d_coeff_7": int(rlc_sum_dlog_div.b.denominator[7].value),
                "g_x": int(points[0].x),
                "g_y": int(points[0].y),
                "ep1_low": int(epns_low[0][0]),
                "en1_low": int(epns_low[0][1]),
                "sp1_low": int(epns_low[0][2] % curve.p),
                "sn1_low": int(epns_low[0][3] % curve.p),
                "ep1_high": int(epns_high[0][0]),
                "en1_high": int(epns_high[0][1]),
                "sp1_high": int(epns_high[0][2] % curve.p),
                "sn1_high": int(epns_high[0][3] % curve.p),
                "q_low_x": int(q_low.x),
                "q_low_y": int(q_low.y),
                "q_high_x": int(q_high.x),
                "q_high_y": int(q_high.y),
                "q_high_shifted_x": int(q_high_shifted.x),
                "q_high_shifted_y": int(q_high_shifted.y),
                "a0_x": int(a0.x),
                "a0_y": int(a0.y),
                "a": int(curve.a),
                "b": int(curve.b),
                "base_rlc": int(rlc_coeff),
            }

            if prime == curve.p:
                cairo_run("ecip_1p", **inputs)
            compiled_circuit = circuit_compile(cairo_program, "ecip_1p")
            values_ptr = flatten(compiled_circuit["constants"]) + [
                limb for v in inputs.values() for limb in int_to_uint384(v)
            ]
            cairo_run(
                "test__circuit",
                values_ptr=values_ptr,
                values_ptr_len=len(values_ptr),
                p=int_to_uint384(curve.p),
                **compiled_circuit,
            )
            cairo_run(
                "ecip_1p_compiled",
                **{k: int_to_uint384(v) for k, v in inputs.items()},
                p=int_to_uint384(curve.p),
            )


def build_msm_hints(
    msm: MSMCalldataBuilder,
) -> tuple[G1Point, G1Point, G1Point, FunctionFelt, G1Point, int]:
    """
    Returns the MSMHint
    """
    scalars_low, scalars_high = msm.scalars_split()

    q_low, sumDlogDivLow = zk_ecip_hint(msm.points, scalars_low)
    sumDlogDivLow.validate_degrees(msm_size=msm.msm_size, batched=True)

    q_high, sumDlogDivHigh = zk_ecip_hint(msm.points, scalars_high)
    sumDlogDivHigh.validate_degrees(msm_size=msm.msm_size, batched=True)

    q_high_shifted, sumDlogDivHighShifted = zk_ecip_hint([q_high], [2**128])
    sumDlogDivHighShifted.validate_degrees(msm_size=1, batched=True)

    msm._hash_inputs_points_scalars_and_result_points(
        q_low,
        q_high,
        q_high_shifted,
    )

    rlc_coeff = msm.transcript.s1
    sum_dlog_div_maybe_batched = (
        sumDlogDivLow * rlc_coeff
        + sumDlogDivHigh * (rlc_coeff * rlc_coeff)
        + sumDlogDivHighShifted * (rlc_coeff * rlc_coeff * rlc_coeff)
    )

    _x_coordinate = msm._retrieve_random_x_coordinate(sum_dlog_div_maybe_batched)
    _x, _y, _ = derive_ec_point_from_X(_x_coordinate, msm.curve_id)
    a0 = G1Point(curve_id=msm.curve_id, x=_x.value, y=_y.value)

    return (q_low, q_high, q_high_shifted, sum_dlog_div_maybe_batched, a0, rlc_coeff)

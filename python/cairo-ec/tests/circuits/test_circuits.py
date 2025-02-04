from typing import Type

import pytest
from ethereum.crypto.finite_field import PrimeField
from hypothesis import assume, given
from hypothesis import strategies as st
from sympy.core.numbers import mod_inverse

from cairo_addons.testing.utils import flatten
from cairo_addons.utils.uint384 import int_to_uint384, uint384_to_int
from cairo_ec.compiler import circuit_compile
from cairo_ec.curve import ECBase

pytestmark = pytest.mark.python_vm


@pytest.fixture(scope="module")
def prime(request):
    return request.config.getoption("prime")


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
        def test_add(self, cairo_program, cairo_run, prime, data):
            inputs = {
                "x": data.draw(st.integers(min_value=0, max_value=prime - 1)),
                "y": data.draw(st.integers(min_value=0, max_value=prime - 1)),
            }
            values_ptr = [limb for v in inputs.values() for limb in int_to_uint384(v)]
            compiled_circuit = circuit_compile(cairo_program, "add")

            expected_output = (inputs["x"] + inputs["y"]) % prime
            cairo_output = cairo_run("add", **inputs) % prime
            circuit_output = (
                uint384_to_int(
                    *cairo_run(
                        "test__circuit",
                        values_ptr=values_ptr,
                        values_ptr_len=len(values_ptr),
                        p=int_to_uint384(prime),
                        **compiled_circuit,
                    )[-compiled_circuit["return_data_size"] :]
                )
                % prime
            )
            compiled_circuit_output = (
                uint384_to_int(
                    **cairo_run(
                        "add_compiled",
                        **{k: int_to_uint384(v) for k, v in inputs.items()},
                        p=int_to_uint384(prime),
                    )
                )
                % prime
            )
            assert (
                cairo_output
                == circuit_output
                == compiled_circuit_output
                == expected_output
            )

        @given(data=st.data())
        def test_sub(self, cairo_program, cairo_run, prime, data):
            inputs = {
                "x": data.draw(st.integers(min_value=0, max_value=prime - 1)),
                "y": data.draw(st.integers(min_value=0, max_value=prime - 1)),
            }
            values_ptr = [limb for v in inputs.values() for limb in int_to_uint384(v)]
            compiled_circuit = circuit_compile(cairo_program, "sub")

            expected_output = (inputs["x"] - inputs["y"]) % prime
            cairo_output = cairo_run("sub", **inputs) % prime
            circuit_output = (
                uint384_to_int(
                    *cairo_run(
                        "test__circuit",
                        values_ptr=values_ptr,
                        values_ptr_len=len(values_ptr),
                        p=int_to_uint384(prime),
                        **compiled_circuit,
                    )[-compiled_circuit["return_data_size"] :]
                )
                % prime
            )
            compiled_circuit_output = (
                uint384_to_int(
                    **cairo_run(
                        "sub_compiled",
                        **{k: int_to_uint384(v) for k, v in inputs.items()},
                        p=int_to_uint384(prime),
                    )
                )
                % prime
            )
            assert (
                cairo_output
                == circuit_output
                == compiled_circuit_output
                == expected_output
            )

        @given(data=st.data())
        def test_mul(self, cairo_program, cairo_run, prime, data):
            inputs = {
                "x": data.draw(st.integers(min_value=0, max_value=prime - 1)),
                "y": data.draw(st.integers(min_value=0, max_value=prime - 1)),
            }
            values_ptr = [limb for v in inputs.values() for limb in int_to_uint384(v)]
            compiled_circuit = circuit_compile(cairo_program, "mul")

            expected_output = (inputs["x"] * inputs["y"]) % prime
            cairo_output = cairo_run("mul", **inputs) % prime
            circuit_output = (
                uint384_to_int(
                    *cairo_run(
                        "test__circuit",
                        values_ptr=values_ptr,
                        values_ptr_len=len(values_ptr),
                        p=int_to_uint384(prime),
                        **compiled_circuit,
                    )[-compiled_circuit["return_data_size"] :]
                )
                % prime
            )
            compiled_circuit_output = (
                uint384_to_int(
                    **cairo_run(
                        "mul_compiled",
                        **{k: int_to_uint384(v) for k, v in inputs.items()},
                        p=int_to_uint384(prime),
                    )
                )
                % prime
            )
            assert (
                cairo_output
                == circuit_output
                == compiled_circuit_output
                == expected_output
            )

        @given(data=st.data())
        def test_div(self, cairo_program, cairo_run, prime, data):
            inputs = {
                "x": data.draw(st.integers(min_value=0, max_value=prime - 1)),
                "y": data.draw(st.integers(min_value=1, max_value=prime - 1)),
            }
            values_ptr = [limb for v in inputs.values() for limb in int_to_uint384(v)]
            compiled_circuit = circuit_compile(cairo_program, "div")

            expected_output = (inputs["x"] * mod_inverse(inputs["y"], prime)) % prime
            cairo_output = cairo_run("div", **inputs) % prime
            circuit_output = (
                uint384_to_int(
                    *cairo_run(
                        "test__circuit",
                        values_ptr=values_ptr,
                        values_ptr_len=len(values_ptr),
                        p=int_to_uint384(prime),
                        **compiled_circuit,
                    )[-compiled_circuit["return_data_size"] :]
                )
                % prime
            )
            compiled_circuit_output = (
                uint384_to_int(
                    **cairo_run(
                        "div_compiled",
                        **{k: int_to_uint384(v) for k, v in inputs.items()},
                        p=int_to_uint384(prime),
                    )
                )
                % prime
            )
            assert (
                cairo_output
                == circuit_output
                == compiled_circuit_output
                == expected_output
            )

        @given(data=st.data())
        def test_diff_ratio(self, cairo_program, cairo_run, prime, data):
            inputs = {
                "x": data.draw(st.integers(min_value=0, max_value=prime - 1)),
                "y": data.draw(st.integers(min_value=0, max_value=prime - 1)),
            }
            assume(inputs["x"] != inputs["y"])
            values_ptr = [limb for v in inputs.values() for limb in int_to_uint384(v)]
            compiled_circuit = circuit_compile(cairo_program, "diff_ratio")

            expected_output = (
                (inputs["x"] - inputs["y"])
                * mod_inverse(inputs["x"] - inputs["y"], prime)
            ) % prime
            cairo_output = cairo_run("diff_ratio", **inputs) % prime
            circuit_output = (
                uint384_to_int(
                    *cairo_run(
                        "test__circuit",
                        values_ptr=values_ptr,
                        values_ptr_len=len(values_ptr),
                        p=int_to_uint384(prime),
                        **compiled_circuit,
                    )[-compiled_circuit["return_data_size"] :]
                )
                % prime
            )
            compiled_circuit_output = (
                uint384_to_int(
                    **cairo_run(
                        "diff_ratio_compiled",
                        **{k: int_to_uint384(v) for k, v in inputs.items()},
                        p=int_to_uint384(prime),
                    )
                )
                % prime
            )
            assert (
                cairo_output
                == circuit_output
                == compiled_circuit_output
                == expected_output
            )

        @given(data=st.data())
        def test_sum_ratio(self, cairo_program, cairo_run, prime, data):
            inputs = {
                "x": data.draw(st.integers(min_value=0, max_value=prime - 1)),
                "y": data.draw(st.integers(min_value=0, max_value=prime - 1)),
            }
            assume(inputs["x"] != -inputs["y"])
            values_ptr = [limb for v in inputs.values() for limb in int_to_uint384(v)]
            compiled_circuit = circuit_compile(cairo_program, "sum_ratio")

            expected_output = (
                (inputs["x"] + inputs["y"])
                * mod_inverse(inputs["x"] + inputs["y"], prime)
            ) % prime
            cairo_output = cairo_run("sum_ratio", **inputs) % prime
            circuit_output = (
                uint384_to_int(
                    *cairo_run(
                        "test__circuit",
                        values_ptr=values_ptr,
                        values_ptr_len=len(values_ptr),
                        p=int_to_uint384(prime),
                        **compiled_circuit,
                    )[-compiled_circuit["return_data_size"] :]
                )
                % prime
            )
            compiled_circuit_output = (
                uint384_to_int(
                    **cairo_run(
                        "sum_ratio_compiled",
                        **{k: int_to_uint384(v) for k, v in inputs.items()},
                        p=int_to_uint384(prime),
                    )
                )
                % prime
            )
            assert (
                cairo_output
                == circuit_output
                == compiled_circuit_output
                == expected_output
            )

        @given(data=st.data())
        def test_inv(self, cairo_program, cairo_run, prime, data):
            inputs = {
                "x": data.draw(st.integers(min_value=1, max_value=prime - 1)),
            }
            compiled_circuit = circuit_compile(cairo_program, "inv")
            values_ptr = flatten(
                compiled_circuit["constants"]
                + [limb for v in inputs.values() for limb in int_to_uint384(v)]
            )

            expected_output = mod_inverse(inputs["x"], prime)
            cairo_output = cairo_run("inv", **inputs) % prime
            circuit_output = (
                uint384_to_int(
                    *cairo_run(
                        "test__circuit",
                        values_ptr=values_ptr,
                        values_ptr_len=len(values_ptr),
                        p=int_to_uint384(prime),
                        **compiled_circuit,
                    )[-compiled_circuit["return_data_size"] :]
                )
                % prime
            )
            compiled_circuit_output = (
                uint384_to_int(
                    **cairo_run(
                        "inv_compiled",
                        **{k: int_to_uint384(v) for k, v in inputs.items()},
                        p=int_to_uint384(prime),
                    )
                )
                % prime
            )
            assert (
                cairo_output
                == circuit_output
                == compiled_circuit_output
                == expected_output
            )

    class TestEcOps:
        @given(data=st.data())
        def test_ec_add(self, cairo_program, cairo_run, curve, data):
            seed_p = data.draw(
                st.integers(min_value=0, max_value=curve.FIELD.PRIME - 1)
            )
            seed_q = data.draw(
                st.integers(min_value=0, max_value=curve.FIELD.PRIME - 1)
            )
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
        def test_ec_double(self, cairo_program, cairo_run, curve, data):
            seed_p = data.draw(
                st.integers(min_value=0, max_value=curve.FIELD.PRIME - 1)
            )
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

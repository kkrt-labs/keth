import pytest
from hypothesis import assume, given
from hypothesis import strategies as st
from sympy.core.numbers import mod_inverse

from cairo_addons.utils.uint384 import int_to_uint384, uint384_to_int
from cairo_ec.compiler import circuit_compile

pytestmark = pytest.mark.python_vm


@pytest.fixture(scope="module")
def prime(request):
    return request.config.getoption("prime")


class TestCircuits:
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
            cairo_output == circuit_output == compiled_circuit_output == expected_output
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
            cairo_output == circuit_output == compiled_circuit_output == expected_output
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
            cairo_output == circuit_output == compiled_circuit_output == expected_output
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
            cairo_output == circuit_output == compiled_circuit_output == expected_output
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
            (inputs["x"] - inputs["y"]) * mod_inverse(inputs["x"] - inputs["y"], prime)
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
            cairo_output == circuit_output == compiled_circuit_output == expected_output
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
            (inputs["x"] + inputs["y"]) * mod_inverse(inputs["x"] + inputs["y"], prime)
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
            cairo_output == circuit_output == compiled_circuit_output == expected_output
        )

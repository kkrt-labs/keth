import pytest
from hypothesis import given
from hypothesis import strategies as st
from starkware.cairo.lang.compiler.program import Program

from cairo_addons.utils.uint384 import int_to_uint384, uint384_to_int
from cairo_ec.compiler import compile_circuit

pytestmark = pytest.mark.python_vm


@pytest.fixture(scope="module")
def simple_circuit(cairo_program: Program):
    start = cairo_program.get_label("test__simple_circuit")
    stop = cairo_program.get_label("test__simple_circuit.return_label") + 1
    return compile_circuit(cairo_program.data[start:stop])


@pytest.fixture(scope="module")
def prime(request):
    return request.config.getoption("prime")


class TestModCircuit:

    class TestSimpleCircuit:
        @given(data=st.data())
        def test_should_pass(self, cairo_run, prime, simple_circuit, data):
            x = data.draw(st.integers(min_value=0, max_value=prime - 1))
            y = data.draw(st.integers(min_value=0, max_value=prime - 1))

            add_mod_offsets, mul_mod_offsets, offset = simple_circuit
            output = cairo_run(
                "test__mod_builtin",
                x=int_to_uint384(x),
                y=int_to_uint384(y),
                p=int_to_uint384(prime),
                add_mod_offsets_ptr=add_mod_offsets,
                add_mod_n=len(add_mod_offsets) // 3,
                mul_mod_offsets_ptr=mul_mod_offsets,
                mul_mod_n=len(mul_mod_offsets) // 3,
                offset=offset,
            )
            assert cairo_run("test__simple_circuit", x=x, y=y) == uint384_to_int(
                *output[-4:]
            )

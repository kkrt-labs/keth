import pytest
from hypothesis import given

pytestmark = pytest.mark.python_vm


class TestModCircuit:

    class TestSum:
        @given(x=..., y=...)
        def test_should_pass(self, request, cairo_run, x: int, y: int):
            prime = request.config.getoption("prime")
            assert cairo_run("test__sum", x=x, y=y) == (x + y) % prime

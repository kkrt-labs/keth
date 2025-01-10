import pytest
from ethereum_types.bytes import Bytes
from hypothesis import given

pytestmark = pytest.mark.python_vm


class TestBytes:
    @given(a=..., b=...)
    def test_Bytes__eq__(self, cairo_run, a: Bytes, b: Bytes):
        assert (a == b) == cairo_run("Bytes__eq__", a, b)

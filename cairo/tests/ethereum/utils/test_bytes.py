from ethereum_types.bytes import Bytes, Bytes20, Bytes32
from hypothesis import given


class TestBytes:
    @given(a=..., b=...)
    def test_Bytes__eq__(self, cairo_run, a: Bytes, b: Bytes):
        assert (a == b) == cairo_run("Bytes__eq__", a, b)

    @given(a=...)
    def test_Bytes20_to_Bytes(self, cairo_run, a: Bytes20):
        assert cairo_run("Bytes20_to_Bytes", a) == Bytes(a)

    @given(a=...)
    def test_Bytes32_to_Bytes(self, cairo_run, a: Bytes32):
        assert cairo_run("Bytes32_to_Bytes", a) == Bytes(a)

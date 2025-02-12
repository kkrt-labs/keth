from typing import List

from ethereum_types.bytes import Bytes, Bytes4, Bytes8, Bytes20, Bytes32
from hypothesis import given
from hypothesis import strategies as st


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

    @given(a=...)
    def test_Bytes8_to_Bytes(self, cairo_run, a: Bytes8):
        assert cairo_run("Bytes8_to_Bytes", a) == Bytes(a)

    @given(input_=st.binary(max_size=1024))
    def test_Bytes_to_be_ListBytes4(self, cairo_run, input_: Bytes):
        res = cairo_run("Bytes_to_be_ListBytes4", input_)
        # Although we are converting to big-endian Bytes4, our serde module _always_
        # deserializes the Bytes4 object as little-endian. Thus, it's right-justified, not left-justified.
        assert res == [
            (bytes(input_[i : i + 4][::-1])).rjust(4, b"\x00")
            for i in range(0, len(input_), 4)
        ]

    @given(a=...)
    def test_ListBytes4_be_to_bytes(self, cairo_run, a: List[Bytes4]):
        # Cairo serializes the bytes4 in little-endian form. Thus the comparison we must make is
        # between the reversed bytes and the input.
        assert cairo_run("ListBytes4_be_to_bytes", a) == b"".join([b[::-1] for b in a])

    @given(a=st.binary(min_size=0, max_size=32))
    def test_Bytes_to_Bytes32(self, cairo_run, a: Bytes):
        assert cairo_run("Bytes_to_Bytes32", a) == Bytes32(a.ljust(32, b"\x00"))

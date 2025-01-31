from typing import List

from ethereum_types.bytes import Bytes, Bytes4, Bytes8, Bytes20, Bytes32
from hypothesis import given
from hypothesis import strategies as st

from tests.utils.errors import strict_raises


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

    @given(input=st.binary(max_size=1024))
    def test_Bytes_to_be_ListBytes4(self, cairo_run, input: Bytes):
        try:
            res = cairo_run("Bytes_to_be_ListBytes4", input)
        except Exception as e:
            with strict_raises(type(e)):
                if len(input) % 4 != 0:
                    raise IndexError
                [
                    int.from_bytes(input[i : i + 4], "big")
                    for i in range(0, len(input), 4)
                ]
            return

        assert res == [
            int.from_bytes(input[i : i + 4], "big") for i in range(0, len(input), 4)
        ]

    @given(a=...)
    def test_ListBytes4_be_to_bytes(self, cairo_run_py, a: List[Bytes4]):
        assert cairo_run_py("ListBytes4_be_to_bytes", a) == b"".join(b for b in a)

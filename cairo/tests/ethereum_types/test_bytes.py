from hypothesis import given

from ethereum_types.bytes import Bytes


class TestBytes:

    class TestEq:
        @given(lhs=..., rhs=...)
        def test_eq(self, cairo_run, lhs: Bytes, rhs: Bytes):
            assert (lhs == rhs) == cairo_run("Bytes__eq__", lhs, rhs)

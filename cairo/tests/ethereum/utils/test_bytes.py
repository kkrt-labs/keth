from typing import List

from ethereum_types.bytes import Bytes, Bytes4, Bytes8, Bytes20, Bytes32, Bytes256
from hypothesis import given
from hypothesis import strategies as st

from cairo_addons.testing.errors import strict_raises
from cairo_addons.testing.hints import patch_hint


class TestBytes:
    @given(a=..., b=...)
    def test_Bytes__add__(self, cairo_run, a: Bytes, b: Bytes):
        assert cairo_run("Bytes__add__", a, b) == a + b

    @given(a=..., b=...)
    def test_Bytes__extend__(self, cairo_run, a: Bytes, b: Bytes):
        cairo_result = cairo_run("Bytes__extend__", a, b)
        a += b
        assert a == cairo_result

    @given(a=..., b=...)
    def test_Bytes__eq__(self, cairo_run, a: Bytes, b: Bytes):
        assert (a == b) == cairo_run("Bytes__eq__", a, b)

    def test_Bytes__eq__should_fail_when_not_equal_and_bad_prover_hint(
        self, cairo_run, cairo_programs, rust_programs
    ):
        a = Bytes(b"a")
        b = Bytes(b"b")
        with patch_hint(
            cairo_programs,
            rust_programs,
            "Bytes__eq__",
            """
ids.is_diff = 0
ids.diff_index = 0
""",
        ):
            with strict_raises(AssertionError):
                cairo_run("Bytes__eq__", a, b)

    def test_Bytes__eq__should_fail_when_equal_and_bad_prover_hint(
        self, cairo_run, cairo_programs, rust_programs
    ):
        a = Bytes(b"a")
        b = Bytes(b"a")
        with patch_hint(
            cairo_programs,
            rust_programs,
            "Bytes__eq__",
            """
ids.is_diff = 1
ids.diff_index = 0
""",
        ):
            with strict_raises(Exception, "assert_not_equal failed"):
                cairo_run("Bytes__eq__", a, b)

    @given(a=..., b=...)
    def test_Bytes__startswith__(self, cairo_run, a: Bytes, b: Bytes):
        assert (a.startswith(b)) == cairo_run("Bytes__startswith__", a, b)
        assert (b.startswith(a)) == cairo_run("Bytes__startswith__", b, a)
        assert (a.startswith(a[0 : len(a) // 2])) == cairo_run(
            "Bytes__startswith__", a, a[0 : len(a) // 2]
        )

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

    @given(a=st.binary(min_size=0, max_size=100))
    def test_Bytes_to_Bytes32(self, cairo_run, a: Bytes):
        try:
            res = cairo_run("Bytes_to_Bytes32", a)
        except Exception:
            with strict_raises(ValueError):
                Bytes32(a)
            return

        assert res == Bytes32(a.ljust(32, b"\x00"))

    @given(a=st.binary(min_size=32, max_size=32), b=st.binary(min_size=32, max_size=32))
    def test_Bytes32__eq__(self, cairo_run, a: Bytes32, b: Bytes32):
        assert (a == b) == cairo_run("Bytes32__eq__", a, b)

    @given(
        a=st.binary(min_size=256, max_size=256), b=st.binary(min_size=256, max_size=256)
    )
    def test_Bytes256__eq__(self, cairo_run, a: Bytes256, b: Bytes256):
        assert (a == b) == cairo_run("Bytes256__eq__", a, b)

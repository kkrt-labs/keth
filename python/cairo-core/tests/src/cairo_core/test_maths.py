import pytest
from hypothesis import Verbosity, given, settings
from hypothesis import strategies as st
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

from cairo_addons.testing.errors import cairo_error
from cairo_addons.testing.hints import patch_hint
from cairo_addons.testing.strategies import felt
from cairo_addons.utils.uint256 import int_to_uint256

pytestmark = pytest.mark.python_vm


class TestMaths:
    class TestSign:
        @given(value=felt)
        def test_sign(self, cairo_run, value):
            sign = cairo_run("sign", value=value)
            assert (
                sign % DEFAULT_PRIME
                == (2 * (0 <= value < DEFAULT_PRIME // 2) - 1) % DEFAULT_PRIME
            )

    class TestAssertUint256Le:
        @given(
            a=st.integers(min_value=0, max_value=2**256 - 1),
            b=st.integers(min_value=0, max_value=2**256 - 1),
        )
        @settings(max_examples=50)
        def test_assert_uint256_le(self, cairo_run, a, b):
            if a > b:
                with pytest.raises(Exception):
                    cairo_run(
                        "test__assert_uint256_le",
                        a=int_to_uint256(a),
                        b=int_to_uint256(b),
                    )
            else:
                cairo_run(
                    "test__assert_uint256_le", a=int_to_uint256(a), b=int_to_uint256(b)
                )

    @given(i=st.integers(min_value=0, max_value=251))
    def test_pow2(self, cairo_run, i):
        res = cairo_run("pow2", i=i)
        assert res == 2**i

    @given(i=st.integers(min_value=0, max_value=31))
    def test_pow256(self, cairo_run, i):
        res = cairo_run("pow256", i=i)
        assert res == 256**i

    @given(
        value=st.integers(min_value=0, max_value=2**248 - 1),
        len_=st.integers(min_value=0, max_value=31),
    )
    def test_felt252_to_bytes_le(self, cairo_run, value, len_):
        res = cairo_run("test__felt252_to_bytes_le", value=value, len=len_)
        try:
            expected = value.to_bytes(len_, "little")
        except OverflowError:
            # If value doesn't fit in len_ bytes, truncate it
            mask = (1 << (len_ * 8)) - 1
            truncated_value = value & mask
            expected = truncated_value.to_bytes(len_, "little")

        assert bytes(res) == expected

    @given(
        value=st.integers(min_value=0, max_value=2**248 - 1),
        len_=st.integers(min_value=32, max_value=DEFAULT_PRIME - 1),
    )
    def test_felt252_to_bytes_le_should_panic_on_len_too_big(
        self, cairo_run, value, len_
    ):
        with cairo_error(message="felt252_to_bytes_le: len must be < 32"):
            cairo_run("test__felt252_to_bytes_le", value=value, len=len_)

    @given(
        value=st.integers(min_value=1, max_value=2**248 - 1),
        len_=st.integers(min_value=1, max_value=31),
    )
    @settings(verbosity=Verbosity.quiet)
    def test_felt252_to_bytes_le_should_panic_on_wrong_output(
        self, cairo_programs, cairo_run_py, value, len_
    ):
        with patch_hint(
            cairo_programs,
            "felt252_to_bytes_le",
            """
mask = (1 << (ids.len * 8)) - 1
truncated_value = ids.value & mask
segments.write_arg(ids.output, [int(b)+1 if b < 255 else 0 for b in truncated_value.to_bytes(length=ids.len, byteorder='little')])
            """,
        ), cairo_error(message="felt252_to_bytes_le: bad output"):
            cairo_run_py("test__felt252_to_bytes_le", value=value, len=len_)

    def test_felt252_to_bytes_le_should_panic_on_wrong_output_noncanonical(
        self, cairo_programs, cairo_run_py
    ):
        value = 0xAABB
        len_ = 2
        with patch_hint(
            cairo_programs,
            "felt252_to_bytes_le",
            """
mask = (1 << (ids.len * 8)) - 1
truncated_value = ids.value & mask
canonical = truncated_value.to_bytes(length=ids.len, byteorder='little')
bad = list(canonical)
if ids.len > 1 and canonical[1] > 0:
    # Cheating: adjust the first two "bytes" so that the weighted sum is preserved,
    # but the output is non-canonical (first byte is >= 256).
    bad[0] = canonical[0] + 256
    bad[1] = canonical[1] - 1
segments.write_arg(ids.output, bad)
            """,
        ), cairo_error(message="felt252_to_bytes_le: byte not in bounds"):
            cairo_run_py("test__felt252_to_bytes_le", value=value, len=len_)

    @given(
        value=st.integers(min_value=256, max_value=2**248 - 1),
        len_=st.integers(min_value=2, max_value=31),
    )
    def test_felt252_to_bytes_be(self, cairo_run, value, len_):
        res = cairo_run("test__felt252_to_bytes_be", value=value, len=len_)
        try:
            expected = value.to_bytes(len_, "big")
        except OverflowError:
            # If value doesn't fit in len_ bytes, truncate it
            mask = (1 << (len_ * 8)) - 1
            truncated_value = value & mask
            expected = truncated_value.to_bytes(len_, "big")

        assert bytes(res) == expected

    @given(
        value=st.integers(min_value=0, max_value=2**248 - 1),
        len_=st.integers(min_value=32, max_value=DEFAULT_PRIME - 1),
    )
    def test_felt252_to_bytes_be_should_panic_on_len_too_big(
        self, cairo_run, value, len_
    ):
        with cairo_error(message="felt252_to_bytes_be: len must be < 32"):
            cairo_run("test__felt252_to_bytes_be", value=value, len=len_)

    @given(
        value=st.integers(min_value=1, max_value=2**248 - 1),
        len_=st.integers(min_value=1, max_value=31),
    )
    @settings(verbosity=Verbosity.quiet)
    def test_felt252_to_bytes_be_should_panic_on_wrong_output(
        self, cairo_programs, cairo_run_py, value, len_
    ):
        with patch_hint(
            cairo_programs,
            "felt252_to_bytes_be",
            """
mask = (1 << (ids.len * 8)) - 1
truncated_value = ids.value & mask
segments.write_arg(ids.output, [int(b) + 1 if b < 255 else 0 for b in truncated_value.to_bytes(length=ids.len, byteorder='big')])
            """,
        ), cairo_error(message="felt252_to_bytes_be: bad output"):
            cairo_run_py("test__felt252_to_bytes_be", value=value, len=len_)

    def test_felt252_to_bytes_be_should_panic_on_wrong_output_noncanonical(
        self, cairo_programs, cairo_run_py
    ):
        value = 0xAABB
        len_ = 2
        with patch_hint(
            cairo_programs,
            "felt252_to_bytes_be",
            """
mask = (1 << (ids.len * 8)) - 1
truncated_value = ids.value & mask
canonical = truncated_value.to_bytes(length=ids.len, byteorder='big')
bad = list(canonical)
if ids.len > 1 and canonical[-2] > 0:
    # Cheating: adjust the last two "bytes" so that the weighted sum remains preserved,
    # but the output is non-canonical (one byte ends up >= 256).
    bad[-1] = canonical[-1] + 256
    bad[-2] = canonical[-2] - 1
segments.write_arg(ids.output, bad)
            """,
        ), cairo_error(message="felt252_to_bytes_be: byte not in bounds"):
            cairo_run_py("test__felt252_to_bytes_be", value=value, len=len_)

    @given(value=st.integers(min_value=0, max_value=DEFAULT_PRIME - 1))
    def test_felt252_bit_length(self, cairo_run, value):
        res = cairo_run("felt252_bit_length", value=value)
        assert res == value.bit_length()

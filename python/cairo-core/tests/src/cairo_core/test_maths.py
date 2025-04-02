import pytest
from ethereum_types.numeric import U256
from hypothesis import Verbosity, given, settings
from hypothesis import strategies as st
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

from cairo_addons.testing.errors import cairo_error
from cairo_addons.testing.hints import patch_hint
from cairo_addons.testing.strategies import felt


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
                    cairo_run("test__assert_uint256_le", a=U256(a), b=U256(b))
            else:
                cairo_run("test__assert_uint256_le", a=U256(a), b=U256(b))

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

    @given(
        value=st.integers(min_value=0, max_value=2**248 - 1),
        len_=st.integers(min_value=0, max_value=251),
    )
    def test_felt252_to_bits_rev(self, cairo_run, value, len_):
        expected = [int(bit) for bit in bin(value)[2:].zfill(len_)[::-1][:len_]]
        res = cairo_run("test__felt252_to_bits_rev", value=value, len=len_)

        assert res == expected

    @given(
        value=st.integers(min_value=1, max_value=2**248 - 1),
        len_=st.integers(min_value=1, max_value=31),
    )
    @settings(verbosity=Verbosity.quiet)
    def test_felt252_to_bits_rev_should_panic_on_wrong_output(
        self, cairo_programs, cairo_run_py, value, len_
    ):
        with patch_hint(
            cairo_programs,
            "felt252_to_bits_rev",
            """
value = ids.value
length = ids.len
dst_ptr = ids.dst

mask = (1 << length) - 1
value_masked = value & mask
bits_used = value_masked.bit_length() or 1
bits = [int(bit) for bit in bin(value_masked)[2:].zfill(length)[::-1]]

# --- Introduce corruption ---
bad_bits = bits[:] # Copy the list
# Flip the first bit (least significant) to make the output incorrect
bad_bits[0] = 1 - bad_bits[0]

ids.bits_used = min(bits_used, length)
segments.load_data(dst_ptr, bad_bits)
        """,
            # Assert that the Cairo code panics with the expected message
        ), cairo_error(message="felt252_to_bits_rev: bad output"):
            cairo_run_py("test__felt252_to_bits_rev", value=value, len=len_)

    @given(
        value=st.integers(min_value=0, max_value=2**248 - 1),
        len_=st.integers(min_value=1, max_value=251),  # Ensure len_ >= 1
    )
    @settings(verbosity=Verbosity.quiet)
    def test_felt252_to_bits_rev_should_panic_on_non_binary_output(
        self, cairo_programs, cairo_run_py, value, len_
    ):
        with patch_hint(
            cairo_programs,
            "felt252_to_bits_rev",
            """
# Get inputs from ids context
value = ids.value
length = ids.len
dst_ptr = ids.dst

mask = (1 << length) - 1
value_masked = value & mask
bits_used = value_masked.bit_length() or 1
bits = [int(bit) for bit in bin(value_masked)[2:].zfill(length)[::-1]]

# --- Introduce non-binary value ---
bad_bits = bits[:] # Copy the list
# Change the first bit (least significant) to an invalid value (e.g., 2)
bad_bits[0] = 2

ids.bits_used = min(bits_used, length)
segments.load_data(dst_ptr, bad_bits)
        """,
            # Assert that the Cairo code panics, likely checking the bit values
            # The exact message depends on the assertion inside the Cairo function.
            # Common patterns might be "bit is not binary" or "bit out of bounds".
        ), cairo_error(message="felt252_to_bits_rev: bits must be 0 or 1"):
            cairo_run_py("test__felt252_to_bits_rev", value=value, len=len_)

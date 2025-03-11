from ethereum.cancun.fork_types import Address
from ethereum.cancun.vm.gas import (
    BLOB_GASPRICE_UPDATE_FRACTION,
    MIN_BLOB_GASPRICE,
    TARGET_BLOB_GAS_PER_BLOCK,
)
from ethereum.utils.numeric import ceil32, taylor_exponential
from ethereum_types.bytes import Bytes, Bytes32
from ethereum_types.numeric import U64, U256, Uint
from hypothesis import given
from hypothesis import strategies as st
from starkware.cairo.lang.instances import PRIME

from cairo_addons.testing.errors import strict_raises
from tests.utils.args_gen import U384
from tests.utils.strategies import small_bytes, uint128, uint256


def taylor_exponential_limited(
    factor: Uint, numerator: Uint, denominator: Uint
) -> Uint:
    """
    Limited version of taylor_exponential that saturates when
    `numerator_accumulated * numerator` is greater than 2**128 - 1
    """
    i = Uint(1)
    output = Uint(0)
    numerator_accumulated = factor * denominator
    while numerator_accumulated > Uint(0):
        output += numerator_accumulated
        value = numerator_accumulated * numerator
        div = denominator * i
        if value > Uint(2**128 - 1):
            return output // denominator
        numerator_accumulated = value // div
        i += Uint(1)
    return output // denominator


class TestNumeric:

    @given(a=uint128, b=uint128)
    def test_min(self, cairo_run, a, b):
        assert min(a, b) == cairo_run("min", a, b)

    @given(a=uint128, b=uint128)
    def test_max(self, cairo_run, a, b):
        assert max(a, b) == cairo_run("max", a, b)

    @given(
        value=uint128,
        div=st.integers(min_value=1, max_value=PRIME // (2**128 - 1) - 1),
    )
    def test_divmod(self, cairo_run, value, div):
        assert list(divmod(value, div)) == cairo_run("divmod", value, div)

    @given(value=...)
    def test_ceil32(self, cairo_run, value: Uint):
        assert ceil32(value) == cairo_run("ceil32", value)

    @given(
        factor=st.just(MIN_BLOB_GASPRICE),
        numerator=st.integers(
            min_value=1, max_value=10 * int(TARGET_BLOB_GAS_PER_BLOCK)
        ).map(Uint),
        denominator=st.just(BLOB_GASPRICE_UPDATE_FRACTION),
    )
    def test_taylor_exponential(
        self, cairo_run, factor: Uint, numerator: Uint, denominator: Uint
    ):
        assert taylor_exponential(factor, numerator, denominator) == cairo_run(
            "taylor_exponential", factor, numerator, denominator
        )

    @given(
        factor=st.just(MIN_BLOB_GASPRICE),
        numerator=st.integers(min_value=1, max_value=100_000_000_000_000_000).map(Uint),
        denominator=st.just(BLOB_GASPRICE_UPDATE_FRACTION),
    )
    def test_taylor_exponential_limited(
        self, cairo_run, factor: Uint, numerator: Uint, denominator: Uint
    ):
        """
        Compares to our limited version of taylor_exponential that saturates
        when `numerator_accumulated * numerator` is greater than 2**128 - 1
        """
        assert taylor_exponential_limited(factor, numerator, denominator) == cairo_run(
            "taylor_exponential", factor, numerator, denominator
        )

    @given(bytes=...)
    def test_U256_from_be_bytes32(self, cairo_run, bytes: Bytes32):
        expected = U256.from_be_bytes(bytes)
        result = cairo_run("U256_from_be_bytes32", bytes)
        assert result == expected

    @given(bytes=...)
    def test_U256_from_le_bytes(self, cairo_run, bytes: Bytes32):
        expected = U256.from_le_bytes(bytes)
        result = cairo_run("U256_from_le_bytes", bytes)
        assert result == expected

    @given(value=...)
    def test_U256_to_be_bytes(self, cairo_run, value: U256):
        expected = value.to_be_bytes32()
        result = cairo_run("U256_to_be_bytes", value)
        assert result == expected

    @given(value=...)
    def test_U256_to_le_bytes(self, cairo_run, value: U256):
        expected = value.to_le_bytes32()
        result = cairo_run("U256_to_le_bytes", value)
        assert result == expected

    @given(a=..., b=...)
    def test_U256__eq__(self, cairo_run, a: U256, b: U256):
        assert (a == b) == cairo_run("U256__eq__", a, b)

    @given(address=...)
    def test_U256_from_be_bytes20(self, cairo_run, address: Address):
        assert U256.from_be_bytes(address) == cairo_run("U256_from_be_bytes20", address)

    @given(value=st.integers(min_value=0, max_value=2**160 - 1).map(U256))
    def test_U256_to_be_bytes20(self, cairo_run, value: U256):
        cairo_result = cairo_run("U256_to_be_bytes20", value)
        assert U256.to_bytes(value, length=20, byteorder="big") == cairo_result

    @given(a=..., b=...)
    def test_U256_le(self, cairo_run, a: U256, b: U256):
        assert (a <= b) == cairo_run("U256_le", a, b)

    @given(a=..., b=...)
    def test_U256_add(self, cairo_run, a: U256, b: U256):
        try:
            cairo_result = cairo_run("U256_add", a, b)
        except Exception as e:
            with strict_raises(type(e)):
                a + b
            return
        assert cairo_result == a + b

    @given(a=..., b=...)
    def test_U256_sub(self, cairo_run, a: U256, b: U256):
        try:
            cairo_result = cairo_run("U256_sub", a, b)
        except Exception as e:
            with strict_raises(type(e)):
                a - b
            return

        assert cairo_result == a - b

    @given(a=..., b=...)
    def test_U256_mul(self, cairo_run, a: U256, b: U256):
        try:
            cairo_result = cairo_run("U256_mul", a, b)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                a * b
            return
        assert cairo_result == a * b

    @given(bytes=small_bytes)
    def test_U64_from_be_bytes(self, cairo_run, bytes: Bytes):
        try:
            result = cairo_run("U64_from_be_bytes", bytes)
        except Exception as e:
            with strict_raises(type(e)):
                U64.from_be_bytes(bytes)
            return
        expected = U64.from_be_bytes(bytes)
        assert result == expected

    # @dev Note Uint type from EELS is unbounded.
    # But Uint_from_be_bytes panics if len(bytes) > 31
    @given(bytes=small_bytes)
    def test_Uint_from_be_bytes(self, cairo_run, bytes: Bytes):
        try:
            assert Uint.from_be_bytes(bytes) == cairo_run("Uint_from_be_bytes", bytes)
        except Exception:
            assert len(bytes) > 31

    @given(
        a=uint256,
        b=st.integers(min_value=2**256 - 1000, max_value=2**256 - 1).map(U256),
    )
    def test_U256_add_with_carry(self, cairo_run, a: U256, b: U256):
        result, carry = cairo_run("U256_add_with_carry", a, b)
        total = int(a) + int(b)
        cairo_total = int(result) + int(carry) * 2**256
        assert total == cairo_total

    # @dev Note Uint type from EELS is unbounded.
    # But U256_to_Uint panics if value > STONE_PRIME - 1
    @given(value=...)
    def test_U256_to_Uint(self, cairo_run, value: U256):
        try:
            assert Uint(value) == cairo_run("U256_to_Uint", value)
        except Exception:
            assert int(value) > PRIME - 1

    @given(bytes=small_bytes)
    def test_U256_from_be_bytes(self, cairo_run, bytes: Bytes):
        try:
            result = cairo_run("U256_from_be_bytes", bytes)
        except Exception as e:
            with strict_raises(type(e)):
                U256.from_be_bytes(bytes)
            return
        assert result == U256.from_be_bytes(bytes)

    @given(bytes=small_bytes)
    def test_Bytes32_from_be_bytes(self, cairo_run, bytes: Bytes):
        try:
            result = cairo_run("Bytes32_from_be_bytes", bytes)
        except Exception as e:
            with strict_raises(type(e)):
                Bytes32(bytes)
            return
        bytes = (
            int.from_bytes(bytes, "big").to_bytes(32, "big")
            if len(bytes) < 32
            else bytes
        )
        assert result == Bytes32(bytes)

    @given(value=st.integers(min_value=0, max_value=PRIME - 1).map(Uint))
    def test_U256_from_felt(self, cairo_run, value: Uint):
        result = cairo_run("U256_from_Uint", value)
        assert result == U256(value)

    @given(a=uint256, b=uint256)
    def test_u256_min(self, cairo_run, a: U256, b: U256):
        result = cairo_run("U256_min", a, b)
        expected = min(a, b)
        assert result == expected

    @given(value=...)
    def test_U256_bit_length(self, cairo_run, value: U256):
        expected = value.bit_length()
        result = cairo_run("U256_bit_length", value)
        assert result == expected

    @given(bytes=st.binary(max_size=512))
    def test_U384_from_be_bytes(self, cairo_run, bytes: Bytes):
        try:
            result = cairo_run("U384_from_be_bytes", bytes)
        except ValueError:
            assert len(bytes) > 48
            return

        expected = U384(int.from_bytes(bytes, "big"))

        assert result == expected

    @given(a=..., b=...)
    def test_U384__eq__(self, cairo_run, a: U384, b: U384):
        assert (a == b) == cairo_run("U384__eq__", a, b)

    @given(value=...)
    def test_U384_is_zero(self, cairo_run, value: U384):
        cairo_result = cairo_run("U384_is_zero", value)
        assert cairo_result == 1 if value == U384(0) else cairo_result == 0

    @given(value=...)
    def test_U384_is_one(self, cairo_run, value: U384):
        cairo_result = cairo_run("U384_is_one", value)
        assert cairo_result == 1 if value == U384(1) else cairo_result == 0

    @given(a=..., b=...)
    def test_U256_max(self, cairo_run, a: U256, b: U256):
        result = cairo_run("U256_max", a, b)
        expected = max(a, b)
        assert result == expected

from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U256, Uint
from hypothesis import given
from hypothesis import strategies as st
from starkware.cairo.lang.instances import PRIME

from ethereum.cancun.fork_types import Address
from ethereum.cancun.vm.gas import BLOB_GASPRICE_UPDATE_FRACTION, MIN_BLOB_GASPRICE
from ethereum.utils.numeric import ceil32, taylor_exponential
from tests.utils.errors import strict_raises
from tests.utils.strategies import uint128


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
        numerator=st.integers(min_value=1, max_value=100_000).map(Uint),
        denominator=st.just(BLOB_GASPRICE_UPDATE_FRACTION),
    )
    def test_taylor_exponential(
        self, cairo_run, factor: Uint, numerator: Uint, denominator: Uint
    ):
        assert taylor_exponential(factor, numerator, denominator) == cairo_run(
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
    def test_U256_from_be_bytes3220(self, cairo_run, address: Address):
        assert U256.from_be_bytes(address) == cairo_run(
            "U256_from_be_bytes3220", address
        )

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

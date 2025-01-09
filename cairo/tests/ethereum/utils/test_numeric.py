import pytest
from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U256, Uint
from hypothesis import given
from hypothesis import strategies as st
from starkware.cairo.lang.instances import PRIME

from ethereum.cancun.vm.gas import BLOB_GASPRICE_UPDATE_FRACTION, MIN_BLOB_GASPRICE
from ethereum.utils.numeric import ceil32, taylor_exponential
from tests.utils.strategies import felt, uint128

pytestmark = pytest.mark.python_vm


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

    @given(value=felt)
    def test_is_zero(self, cairo_run, value):
        assert (value == 0) == cairo_run("is_zero", value)

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
    def test_U256_from_be_bytes(self, cairo_run, bytes: Bytes32):
        expected = U256.from_be_bytes(bytes)
        result = cairo_run("U256_from_be_bytes", bytes)
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

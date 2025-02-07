from ethereum.cancun.transactions import (
    AccessListTransaction,
    BlobTransaction,
    FeeMarketTransaction,
    LegacyTransaction,
    Transaction,
)
from hypothesis import assume, given


def _transaction_type(tx: Transaction) -> int:
    if isinstance(tx, LegacyTransaction):
        return 0
    elif isinstance(tx, AccessListTransaction):
        return 1
    elif isinstance(tx, FeeMarketTransaction):
        return 2
    elif isinstance(tx, BlobTransaction):
        return 3


class TestTransactionImpl:
    @given(tx=...)
    def test_get_transaction_type(self, cairo_run, tx: Transaction):
        """Test that get_transaction_type returns the correct type for each transaction variant"""
        tx_type = _transaction_type(tx)
        result_cairo = cairo_run("get_transaction_type", tx)
        assert int(result_cairo) == tx_type

    @given(tx=...)
    def test_get_gas(self, cairo_run, tx: Transaction):
        """Test that get_gas returns the correct gas value for each transaction variant"""
        gas = tx.gas
        result_cairo = cairo_run("get_gas", tx)
        assert result_cairo == gas

    @given(tx=...)  # TODO: Add transaction strategy
    def test_get_r(self, cairo_run, tx: Transaction):
        """Test that get_r returns the correct r value for each transaction variant"""
        r = tx.r
        result_cairo = cairo_run("get_r", tx)
        assert result_cairo == r

    @given(tx=...)
    def test_get_s(self, cairo_run, tx: Transaction):
        """Test that get_s returns the correct s value for each transaction variant"""
        s = tx.s
        result_cairo = cairo_run("get_s", tx)
        assert result_cairo == s

    @given(tx=...)
    def test_get_max_fee_per_gas(self, cairo_run, tx: Transaction):
        """Test that get_max_fee_per_gas returns the correct value for FeeMarket and Blob transactions"""

        assume(isinstance(tx, FeeMarketTransaction) or isinstance(tx, BlobTransaction))
        max_fee_per_gas = tx.max_fee_per_gas
        result_cairo = cairo_run("get_max_fee_per_gas", tx)
        assert result_cairo == max_fee_per_gas

    @given(tx=...)
    def test_get_max_priority_fee_per_gas(self, cairo_run, tx: Transaction):
        """Test that get_max_priority_fee_per_gas returns the correct value for FeeMarket and Blob transactions"""
        assume(isinstance(tx, FeeMarketTransaction) or isinstance(tx, BlobTransaction))
        max_priority_fee_per_gas = tx.max_priority_fee_per_gas
        result_cairo = cairo_run("get_max_priority_fee_per_gas", tx)
        assert result_cairo == max_priority_fee_per_gas

    @given(tx=...)
    def test_get_gas_price(self, cairo_run, tx: Transaction):
        """Test that get_gas_price returns the correct value for Legacy and AccessList transactions"""
        assume(
            isinstance(tx, LegacyTransaction) or isinstance(tx, AccessListTransaction)
        )
        gas_price = tx.gas_price
        result_cairo = cairo_run("get_gas_price", tx)
        assert result_cairo == gas_price

    @given(tx=...)  # TODO: Add transaction strategy
    def test_get_nonce(self, cairo_run, tx: Transaction):
        """Test that get_nonce returns the correct nonce for each transaction variant"""
        nonce = tx.nonce
        result_cairo = cairo_run("get_nonce", tx)
        assert result_cairo == nonce

    @given(tx=...)
    def test_get_value(self, cairo_run, tx: Transaction):
        """Test that get_value returns the correct value for each transaction variant"""
        value = tx.value
        result_cairo = cairo_run("get_value", tx)
        assert result_cairo == value

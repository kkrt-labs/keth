import hashlib
from typing import Union

from ethereum.cancun.fork_types import Address
from ethereum.cancun.transactions import (
    AccessListTransaction,
    BlobTransaction,
    FeeMarketTransaction,
    LegacyTransaction,
    Transaction,
)
from ethereum_types.bytes import Bytes0
from hypothesis import assume, given

from tests.utils.hash_utils import LegacyTransaction__hash__


def _transaction_type(tx: Transaction) -> int:
    if isinstance(tx, LegacyTransaction):
        return 0
    elif isinstance(tx, AccessListTransaction):
        return 1
    elif isinstance(tx, FeeMarketTransaction):
        return 2
    elif isinstance(tx, BlobTransaction):
        return 3


class TestUnionBytes0Address:
    @given(to=...)
    def test_To__hash__(self, cairo_run, to: Union[Bytes0, Address]):
        assert hashlib.blake2s(to).digest() == cairo_run("To__hash__", to)


class TestLegacyTransaction:
    @given(tx=...)
    def test_LegacyTransaction__hash__(self, cairo_run, tx: LegacyTransaction):
        assert LegacyTransaction__hash__(tx) == cairo_run(
            "LegacyTransaction__hash__", tx
        )


class TestTransactionImpl:
    @given(tx=...)
    def test_get_transaction_type(self, cairo_run, tx: Transaction):
        tx_type = _transaction_type(tx)
        result_cairo = cairo_run("get_transaction_type", tx)
        assert int(result_cairo) == tx_type

    @given(tx=...)
    def test_get_gas(self, cairo_run, tx: Transaction):
        gas = tx.gas
        result_cairo = cairo_run("get_gas", tx)
        assert result_cairo == gas

    @given(tx=...)
    def test_get_r(self, cairo_run, tx: Transaction):
        r = tx.r
        result_cairo = cairo_run("get_r", tx)
        assert result_cairo == r

    @given(tx=...)
    def test_get_s(self, cairo_run, tx: Transaction):
        s = tx.s
        result_cairo = cairo_run("get_s", tx)
        assert result_cairo == s

    @given(tx=...)
    def test_get_max_fee_per_gas(self, cairo_run, tx: Transaction):
        assume(isinstance(tx, FeeMarketTransaction) or isinstance(tx, BlobTransaction))
        max_fee_per_gas = tx.max_fee_per_gas
        result_cairo = cairo_run("get_max_fee_per_gas", tx)
        assert result_cairo == max_fee_per_gas

    @given(tx=...)
    def test_get_max_priority_fee_per_gas(self, cairo_run, tx: Transaction):
        assume(isinstance(tx, FeeMarketTransaction) or isinstance(tx, BlobTransaction))
        max_priority_fee_per_gas = tx.max_priority_fee_per_gas
        result_cairo = cairo_run("get_max_priority_fee_per_gas", tx)
        assert result_cairo == max_priority_fee_per_gas

    @given(tx=...)
    def test_get_gas_price(self, cairo_run, tx: Transaction):
        assume(
            isinstance(tx, LegacyTransaction) or isinstance(tx, AccessListTransaction)
        )
        gas_price = tx.gas_price
        result_cairo = cairo_run("get_gas_price", tx)
        assert result_cairo == gas_price

    @given(tx=...)
    def test_get_nonce(self, cairo_run, tx: Transaction):
        nonce = tx.nonce
        result_cairo = cairo_run("get_nonce", tx)
        assert result_cairo == nonce

    @given(tx=...)
    def test_get_value(self, cairo_run, tx: Transaction):
        value = tx.value
        result_cairo = cairo_run("get_value", tx)
        assert result_cairo == value

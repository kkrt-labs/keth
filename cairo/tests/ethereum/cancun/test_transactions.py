from ethereum_types.numeric import U64
from hypothesis import given

from ethereum.cancun.transactions import (
    AccessListTransaction,
    BlobTransaction,
    FeeMarketTransaction,
    LegacyTransaction,
    Transaction,
    calculate_intrinsic_cost,
    signing_hash_155,
    signing_hash_1559,
    signing_hash_2930,
    signing_hash_4844,
    signing_hash_pre155,
    validate_transaction,
)
from tests.utils.errors import strict_raises


class TestTransactions:
    @given(tx=...)
    def test_calculate_intrinsic_cost(self, cairo_run, tx: Transaction):
        assert calculate_intrinsic_cost(tx) == cairo_run("calculate_intrinsic_cost", tx)

    @given(tx=...)
    def test_validate_transaction(self, cairo_run_py, tx: Transaction):
        try:
            result_cairo = cairo_run_py("validate_transaction", tx)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                validate_transaction(tx)
            return

        assert result_cairo == validate_transaction(tx)

    @given(tx=...)
    def test_signing_hash_pre155(self, cairo_run, tx: LegacyTransaction):
        """Test pre-EIP155 transaction signing hash computation"""
        try:
            cairo_result = cairo_run("signing_hash_pre155", tx)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                signing_hash_pre155(tx)
            return

        assert signing_hash_pre155(tx) == cairo_result

    @given(tx=..., chain_id=...)
    def test_signing_hash_155(self, cairo_run, tx: LegacyTransaction, chain_id: U64):
        """Test EIP-155 transaction signing hash computation"""
        try:
            cairo_result = cairo_run("signing_hash_155", tx, chain_id)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                signing_hash_155(tx, chain_id)
            return

        assert signing_hash_155(tx, chain_id) == cairo_result

    @given(tx=...)
    def test_signing_hash_2930(self, cairo_run, tx: AccessListTransaction):
        """Test EIP-2930 transaction signing hash computation"""
        try:
            cairo_result = cairo_run("signing_hash_2930", tx)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                signing_hash_2930(tx)
            return

        assert signing_hash_2930(tx) == cairo_result

    @given(tx=...)
    def test_signing_hash_1559(self, cairo_run, tx: FeeMarketTransaction):
        """Test EIP-1559 transaction signing hash computation"""
        try:
            cairo_result = cairo_run("signing_hash_1559", tx)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                signing_hash_1559(tx)
            return

        assert signing_hash_1559(tx) == cairo_result

    @given(tx=...)
    def test_signing_hash_4844(self, cairo_run, tx: BlobTransaction):
        """Test EIP-4844 transaction signing hash computation"""
        try:
            cairo_result = cairo_run("signing_hash_4844", tx)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                signing_hash_4844(tx)
            return
        assert signing_hash_4844(tx) == cairo_result

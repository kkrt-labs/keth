from ethereum.cancun.transactions import (
    AccessListTransaction,
    BlobTransaction,
    FeeMarketTransaction,
    LegacyTransaction,
    Transaction,
    calculate_intrinsic_cost,
    encode_transaction,
    recover_sender,
    signing_hash_155,
    signing_hash_1559,
    signing_hash_2930,
    signing_hash_4844,
    signing_hash_pre155,
    validate_transaction,
)
from ethereum_types.numeric import U64
from hypothesis import given

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
        cairo_result = cairo_run("signing_hash_pre155", tx)
        assert signing_hash_pre155(tx) == cairo_result

    @given(tx=..., chain_id=...)
    def test_signing_hash_155(self, cairo_run, tx: LegacyTransaction, chain_id: U64):
        cairo_result = cairo_run("signing_hash_155", tx, chain_id)
        assert signing_hash_155(tx, chain_id) == cairo_result

    @given(tx=...)
    def test_signing_hash_2930(self, cairo_run, tx: AccessListTransaction):
        cairo_result = cairo_run("signing_hash_2930", tx)
        assert signing_hash_2930(tx) == cairo_result

    @given(tx=...)
    def test_signing_hash_1559(self, cairo_run, tx: FeeMarketTransaction):
        cairo_result = cairo_run("signing_hash_1559", tx)
        assert signing_hash_1559(tx) == cairo_result

    @given(tx=...)
    def test_signing_hash_4844(self, cairo_run, tx: BlobTransaction):
        cairo_result = cairo_run("signing_hash_4844", tx)
        assert signing_hash_4844(tx) == cairo_result

    @given(chain_id=..., tx=...)
    def test_recover_sender(self, cairo_run_py, chain_id: U64, tx: Transaction):
        try:
            # TODO: replace cairo_run_py by cairo_run once garaga hints are implemented in Rust
            cairo_result = cairo_run_py("recover_sender", chain_id, tx)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                recover_sender(chain_id, tx)
            return

        assert recover_sender(chain_id, tx) == cairo_result

    @given(tx=...)
    def test_decode_transaction(self, cairo_run, tx: Transaction):
        encoded_tx = encode_transaction(tx)
        decoded_tx = cairo_run("decode_transaction", encoded_tx)
        assert decoded_tx == tx

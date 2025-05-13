from typing import Union

from ethereum.cancun.transactions import (
    AccessListTransaction,
    BlobTransaction,
    FeeMarketTransaction,
    LegacyTransaction,
    Transaction,
    calculate_intrinsic_cost,
    encode_transaction,
    get_transaction_hash,
    recover_sender,
    signing_hash_155,
    signing_hash_1559,
    signing_hash_2930,
    signing_hash_4844,
    signing_hash_pre155,
    validate_transaction,
)
from ethereum_types.bytes import Bytes, Bytes0
from ethereum_types.numeric import U64, U256, Uint
from hypothesis import example, given

from cairo_addons.testing.errors import strict_raises


class TestTransactions:
    @given(tx=...)
    def test_calculate_intrinsic_cost(self, cairo_run, tx: Transaction):
        assert calculate_intrinsic_cost(tx) == cairo_run("calculate_intrinsic_cost", tx)

    @given(tx=...)
    # Test case where contract creation code size is not valid
    @example(
        tx=LegacyTransaction(
            value=U256(0),
            nonce=U256(0),
            data=Bytes(b"1" * 49153),
            to=Bytes0(),
            gas=Uint(2_000_000),
            gas_price=Uint(0),
            v=U256(0),
            r=U256(0),
            s=U256(0),
        )
    )
    def test_validate_transaction(self, cairo_run, tx: Transaction):
        try:
            result_cairo = cairo_run("validate_transaction", tx)
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
    def test_recover_sender(self, cairo_run, chain_id: U64, tx: Transaction):
        try:
            cairo_result = cairo_run("recover_sender", chain_id, tx)
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

    @given(tx=...)
    def test_get_transaction_hash(self, cairo_run, tx: Union[Bytes, LegacyTransaction]):
        encoded_tx = cairo_run("get_transaction_hash", tx)
        assert encoded_tx == get_transaction_hash(tx)
from typing import Sequence, Tuple, Union

import pytest
from ethereum.prague.blocks import (
    Header,
    Log,
    Receipt,
    Withdrawal,
)
from ethereum.prague.fork_types import Account, Address, Bloom, encode_account
from ethereum.prague.transactions import (
    Access,
    AccessListTransaction,
    BlobTransaction,
    FeeMarketTransaction,
    LegacyTransaction,
    Transaction,
    encode_transaction,
)
from ethereum_rlp.rlp import (
    Extended,
    decode,
    decode_item_length,
    decode_joined_encodings,
    decode_to,
    decode_to_bytes,
    decode_to_sequence,
    encode,
    encode_bytes,
    encode_sequence,
    join_encodings,
)
from ethereum_types.bytes import Bytes, Bytes0, Bytes8, Bytes32
from ethereum_types.numeric import U64, U256, Uint
from hypothesis import assume, given

from cairo_addons.testing.errors import cairo_error


class TestRlp:
    class TestEncode:
        @given(raw_data=...)
        def test_encode(self, cairo_run, raw_data: Extended):
            assert encode(raw_data) == cairo_run("encode", raw_data)

        @given(raw_uint=...)
        def test_encode_uint(self, cairo_run, raw_uint: Union[Uint, bool]):
            assert encode(raw_uint) == cairo_run("encode_uint", raw_uint)

        @given(raw_uint256=...)
        def test_encode_u256(self, cairo_run, raw_uint256: U256):
            assert encode(raw_uint256) == cairo_run("encode_u256", raw_uint256)

        @given(raw_uint256=...)
        def test_encode_u256_little(self, cairo_run, raw_uint256: U256):
            assert encode(raw_uint256.to_be_bytes()[::-1]) == cairo_run(
                "encode_u256_little", raw_uint256
            )

        @given(raw_bytes=...)
        def test_encode_bytes(self, cairo_run, raw_bytes: Bytes):
            assert encode_bytes(raw_bytes) == cairo_run("encode_bytes", raw_bytes)

        @pytest.mark.slow
        @given(raw_sequence=...)
        def test_encode_sequence(self, cairo_run, raw_sequence: Sequence[Extended]):
            assert encode_sequence(raw_sequence) == cairo_run(
                "encode_sequence", raw_sequence
            )

        @pytest.mark.slow
        @given(raw_sequence=...)
        def test_join_encodings(self, cairo_run, raw_sequence: Sequence[Extended]):
            assert join_encodings(raw_sequence) == cairo_run(
                "join_encodings", raw_sequence
            )

        @given(address=...)
        def test_encode_address(self, cairo_run, address: Address):
            assert encode(address) == cairo_run("encode_address", address)

        @given(raw_bytes32=...)
        def test_encode_bytes32(self, cairo_run, raw_bytes32: Bytes32):
            assert encode(raw_bytes32) == cairo_run("encode_bytes32", raw_bytes32)

        @given(raw_tuple_bytes32=...)
        def test_encode_tuple_bytes32(
            self, cairo_run, raw_tuple_bytes32: Tuple[Bytes32, ...]
        ):
            assert encode(raw_tuple_bytes32) == cairo_run(
                "encode_tuple_bytes32", raw_tuple_bytes32
            )

        @given(to=...)
        def test_encode_to(self, cairo_run, to: Union[Bytes0, Address]):
            assert encode(to) == cairo_run("encode_to", to)

        @given(raw_account_data=..., storage_root=...)
        def test_encode_account(
            self, cairo_run, raw_account_data: Account, storage_root: Bytes
        ):
            assert encode_account(raw_account_data, storage_root) == cairo_run(
                "encode_account", raw_account_data, storage_root
            )

        @given(tx=...)
        def test_encode_legacy_transaction(self, cairo_run, tx: LegacyTransaction):
            assert encode(tx) == cairo_run("encode_legacy_transaction", tx)

        @pytest.mark.slow
        @given(log=...)
        def test_encode_log(self, cairo_run, log: Log):
            assert encode(log) == cairo_run("encode_log", log)

        @given(tuple_log=...)
        def test_encode_tuple_log(self, cairo_run, tuple_log: Tuple[Log, ...]):
            assert encode(tuple_log) == cairo_run("encode_tuple_log", tuple_log)

        @given(bloom=...)
        def test_encode_bloom(self, cairo_run, bloom: Bloom):
            assert encode(bloom) == cairo_run("encode_bloom", bloom)

        @pytest.mark.slow
        @given(receipt=...)
        def test_encode_receipt(self, cairo_run, receipt: Receipt):
            assert encode(receipt) == cairo_run("encode_receipt", receipt)

        @given(withdrawal=...)
        def test_encode_withdrawal(self, cairo_run, withdrawal: Withdrawal):
            assert encode(withdrawal) == cairo_run("encode_withdrawal", withdrawal)

        @given(tuple_access_list=...)
        def test_encode_tuple_access_list(
            self,
            cairo_run,
            tuple_access_list: Tuple[Access, ...],
        ):
            assert encode(tuple_access_list) == cairo_run(
                "encode_tuple_access_list", tuple_access_list
            )

        @given(access_list=...)
        def test_encode_access_list(self, cairo_run, access_list: Access):
            assert encode(access_list) == cairo_run("encode_access_list", access_list)

        @given(tx=...)
        def test_encode_access_list_transaction(
            self, cairo_run, tx: AccessListTransaction
        ):
            assert encode_transaction(tx) == cairo_run(
                "encode_access_list_transaction", tx
            )

        @given(tx=...)
        def test_encode_fee_market_transaction(
            self, cairo_run, tx: FeeMarketTransaction
        ):
            assert encode_transaction(tx) == cairo_run(
                "encode_fee_market_transaction", tx
            )

        @given(tx=...)
        def test_encode_blob_transaction(self, cairo_run, tx: BlobTransaction):
            assert encode_transaction(tx) == cairo_run("encode_blob_transaction", tx)

        @given(tx=...)
        def test_encode_transaction(self, cairo_run, tx: Transaction):
            # encode_transaction(legacy_tx) return tx and not RLP encoded bytes
            assert encode_transaction(tx) == cairo_run("encode_transaction", tx)

        @given(tx=...)
        def test_encode_legacy_transaction_for_signing(
            self, cairo_run, tx: LegacyTransaction
        ):
            # <https://github.com/ethereum/execution-specs/blob/master/src/ethereum/prague/transactions.py#L298>
            result = encode(
                (
                    tx.nonce,
                    tx.gas_price,
                    tx.gas,
                    tx.to,
                    tx.value,
                    tx.data,
                )
            )
            assert result == cairo_run("encode_legacy_transaction_for_signing", tx)

        @given(tx=..., chain_id=...)
        def test_encode_eip155_transaction_for_signing(
            self, cairo_run, tx: LegacyTransaction, chain_id: U64
        ):
            # <https://github.com/ethereum/execution-specs/blob/master/src/ethereum/prague/transactions.py#L326>
            assert encode(
                (
                    tx.nonce,
                    tx.gas_price,
                    tx.gas,
                    tx.to,
                    tx.value,
                    tx.data,
                    chain_id,
                    Uint(0),
                    Uint(0),
                )
            ) == cairo_run("encode_eip155_transaction_for_signing", tx, chain_id)

        @given(tx=...)
        def test_encode_access_list_transaction_for_signing(
            self, cairo_run, tx: AccessListTransaction
        ):
            # <https://github.com/ethereum/execution-specs/blob/master/src/ethereum/prague/transactions.py#L359>
            result = b"\x01" + encode(
                (
                    tx.chain_id,
                    tx.nonce,
                    tx.gas_price,
                    tx.gas,
                    tx.to,
                    tx.value,
                    tx.data,
                    tx.access_list,
                )
            )
            assert result == cairo_run("encode_access_list_transaction_for_signing", tx)

        @given(tx=...)
        def test_encode_fee_market_transaction_for_signing(
            self, cairo_run, tx: FeeMarketTransaction
        ):
            # <https://github.com/ethereum/execution-specs/blob/master/src/ethereum/prague/transactions.py#L390>
            result = b"\x02" + encode(
                (
                    tx.chain_id,
                    tx.nonce,
                    tx.max_priority_fee_per_gas,
                    tx.max_fee_per_gas,
                    tx.gas,
                    tx.to,
                    tx.value,
                    tx.data,
                    tx.access_list,
                )
            )
            assert result == cairo_run("encode_fee_market_transaction_for_signing", tx)

        @given(tx=...)
        def test_encode_blob_transaction_for_signing(
            self, cairo_run, tx: BlobTransaction
        ):
            # <https://github.com/ethereum/execution-specs/blob/master/src/ethereum/prague/transactions.py#L422>
            result = b"\x03" + encode(
                (
                    tx.chain_id,
                    tx.nonce,
                    tx.max_priority_fee_per_gas,
                    tx.max_fee_per_gas,
                    tx.gas,
                    tx.to,
                    tx.value,
                    tx.data,
                    tx.access_list,
                    tx.max_fee_per_blob_gas,
                    tx.blob_versioned_hashes,
                )
            )
            assert result == cairo_run("encode_blob_transaction_for_signing", tx)

        @given(bytes8=...)
        def test_encode_bytes8(self, cairo_run, bytes8: Bytes8):
            assert encode(bytes8) == cairo_run("encode_bytes8", bytes8)

        @given(header=...)
        def test_encode_header(self, cairo_run, header: Header):
            assert encode(header) == cairo_run("encode_header", header)

    class TestDecode:
        @given(raw_data=...)
        def test_decode(self, cairo_run, raw_data: Extended):
            assert decode(encode(raw_data)) == cairo_run("decode", encode(raw_data))

        @given(raw_bytes=...)
        def test_decode_to_bytes(self, cairo_run, raw_bytes: Bytes):
            encoded_bytes = encode_bytes(raw_bytes)
            assert decode_to_bytes(encoded_bytes) == cairo_run(
                "decode_to_bytes", encoded_bytes
            )

        @given(encoded_bytes=...)
        def test_decode_to_bytes_should_raise(self, cairo_run, encoded_bytes: Bytes):
            """
            The cairo implementation of decode_to_bytes raises more often than the
            eth-rlp implementation because this latter accepts negative lengths.
            See https://github.com/ethereum/execution-specs/issues/1035
            """
            decoded_bytes = None
            try:
                decoded_bytes = cairo_run("decode_to_bytes", encoded_bytes)
            except Exception:
                pass
            if decoded_bytes is not None:
                assert decoded_bytes == decode_to_bytes(encoded_bytes)

        @pytest.mark.slow
        @given(raw_data=...)
        def test_decode_to_sequence(self, cairo_run, raw_data: Sequence[Extended]):
            assume(isinstance(raw_data, list))
            encoded_sequence = encode(raw_data)
            assert decode_to_sequence(encoded_sequence) == cairo_run(
                "decode_to_sequence", encoded_sequence
            )

        @given(raw_sequence=...)
        def test_decode_joined_encodings(
            self, cairo_run, raw_sequence: Tuple[Bytes, ...]
        ):
            joined_encodings = b"".join(encode_bytes(raw) for raw in raw_sequence)
            assert decode_joined_encodings(joined_encodings) == cairo_run(
                "decode_joined_encodings", joined_encodings
            )

        @given(raw_bytes=...)
        def test_decode_item_length(self, cairo_run, raw_bytes: Bytes):
            encoded_bytes = encode_bytes(raw_bytes)
            assert decode_item_length(encoded_bytes) == cairo_run(
                "decode_item_length", encoded_bytes
            )

        @pytest.mark.parametrize("encoded_data", [b"", b"\xb9", b"\xf8"])
        def test_decode_item_length_should_raise(self, cairo_run, encoded_data: Bytes):
            with pytest.raises(Exception):
                decode_item_length(encoded_data)

            with cairo_error():
                cairo_run("decode_item_length", encoded_data)

        @given(tx=...)
        def test_decode_to_access_list_transaction(
            self, cairo_run, tx: AccessListTransaction
        ):
            encoded_tx = encode_transaction(tx)

            # Remove the type byte (0x01)
            encoded_tx_without_type = encoded_tx[1:]

            decoded_tx = cairo_run(
                "decode_to_access_list_transaction", encoded_tx_without_type
            )

            assert decoded_tx == tx

        @given(tx=...)
        def test_decode_to_fee_market_transaction(
            self, cairo_run, tx: FeeMarketTransaction
        ):
            encoded_tx = encode_transaction(tx)

            # Remove the type byte (0x02) since decode_to_fee_market_transaction expects only the RLP part
            encoded_tx_without_type = encoded_tx[1:]

            decoded_tx = cairo_run(
                "decode_to_fee_market_transaction", encoded_tx_without_type
            )

            assert decoded_tx == tx

        @given(tx=...)
        def test_decode_to_blob_transaction(self, cairo_run, tx: BlobTransaction):
            encoded_tx = encode_transaction(tx)

            # Remove the type byte (0x03) since decode_to_blob_transaction expects only the RLP part
            encoded_tx_without_type = encoded_tx[1:]

            decoded_tx = cairo_run(
                "decode_to_blob_transaction", encoded_tx_without_type
            )

            assert decoded_tx == tx

        @given(receipt=...)
        def test_decode_to_receipt(self, cairo_run, receipt: Receipt):
            encoded_receipt = encode(receipt)
            decoded_receipt_cairo = cairo_run("decode_to_receipt", encoded_receipt)
            decoded_receipt = decode_to(Receipt, encoded_receipt)
            assert decoded_receipt_cairo == decoded_receipt

    class TestU256:
        @given(value=...)
        def test_u256_from_rlp(self, cairo_run, value: U256):
            encoding = encode(value)
            assert U256(int.from_bytes(decode(encoding), "big")) == cairo_run(
                "U256_from_rlp", encoding
            )

    class TestExtendedImpl:
        @given(left=..., right=...)
        def test_eq(self, cairo_run, left: Extended, right: Extended):
            eq_py = (left == right) and type(left) is type(right)
            eq_cairo = cairo_run("Extended__eq__", left, right)
            assert eq_py == eq_cairo

    class TestAccount:
        @given(account=...)
        def test_account_rlp(self, cairo_run, account: Account):
            # Python from / to rlp
            rlp_encoded = account.to_rlp()
            decoded = Account.from_rlp(rlp_encoded)
            # Note: rlp decoding does not include the code, so we don't compare it.
            assert decoded.nonce == account.nonce
            assert decoded.balance == account.balance
            assert decoded.storage_root == account.storage_root
            assert decoded.code_hash == account.code_hash
            # RLP decoding should never yield a code, as it's not part of the RLP encoding.
            assert decoded.code is None

            # Cairo from rlp
            cairo_decoded, _ = cairo_run("Account_from_rlp", encoding=rlp_encoded)
            assert cairo_decoded == decoded

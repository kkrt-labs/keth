from typing import Sequence, Tuple, Union

import pytest
from ethereum_types.bytes import Bytes, Bytes0, Bytes32
from ethereum_types.numeric import U256, Uint
from hypothesis import assume, given, settings

from ethereum.cancun.blocks import Log, Receipt, Withdrawal
from ethereum.cancun.fork_types import Account, Address, Bloom, encode_account
from ethereum.cancun.transactions import LegacyTransaction
from ethereum.rlp import (
    Extended,
    decode,
    decode_item_length,
    decode_joined_encodings,
    decode_to_bytes,
    decode_to_sequence,
    encode,
    encode_bytes,
    encode_sequence,
    get_joined_encodings,
    rlp_hash,
)
from tests.utils.errors import cairo_error


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
        @settings(max_examples=300)
        @given(raw_sequence=...)
        def test_encode_sequence(self, cairo_run, raw_sequence: Sequence[Extended]):
            assert encode_sequence(raw_sequence) == cairo_run(
                "encode_sequence", raw_sequence
            )

        @pytest.mark.slow
        @settings(max_examples=300)
        @given(raw_sequence=...)
        def test_get_joined_encodings(
            self, cairo_run, raw_sequence: Sequence[Extended]
        ):
            assert get_joined_encodings(raw_sequence) == cairo_run(
                "get_joined_encodings", raw_sequence
            )

        @given(raw_bytes=...)
        def test_rlp_hash(self, cairo_run, raw_bytes: Bytes):
            assert rlp_hash(raw_bytes) == cairo_run("rlp_hash", raw_bytes)

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
        @settings(max_examples=300)
        @given(log=...)
        def test_encode_log(self, cairo_run, log: Log):
            assert encode(log) == cairo_run("encode_log", log)

        @pytest.mark.slow
        @settings(max_examples=200)
        @given(tuple_log=...)
        def test_encode_tuple_log(self, cairo_run, tuple_log: Tuple[Log, ...]):
            assert encode(tuple_log) == cairo_run("encode_tuple_log", tuple_log)

        @given(bloom=...)
        def test_encode_bloom(self, cairo_run, bloom: Bloom):
            assert encode(bloom) == cairo_run("encode_bloom", bloom)

        @pytest.mark.slow
        @settings(max_examples=200)
        @given(receipt=...)
        def test_encode_receipt(self, cairo_run, receipt: Receipt):
            assert encode(receipt) == cairo_run("encode_receipt", receipt)

        @given(withdrawal=...)
        def test_encode_withdrawal(self, cairo_run, withdrawal: Withdrawal):
            assert encode(withdrawal) == cairo_run("encode_withdrawal", withdrawal)

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
        @settings(max_examples=300)
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

from typing import Tuple

import pytest
from hypothesis import assume, given
from hypothesis import strategies as st

from ethereum.base_types import Bytes
from ethereum.rlp import (
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
        @given(raw_bytes=...)
        def test_encode_bytes(self, cairo_run, raw_bytes: Bytes):
            assert encode_bytes(raw_bytes) == cairo_run("encode_bytes", raw_bytes)

        @given(raw_sequence=...)
        def test_get_joined_encodings(self, cairo_run, raw_sequence: Tuple[Bytes, ...]):
            assert get_joined_encodings(raw_sequence) == cairo_run(
                "get_joined_encodings", raw_sequence
            )

        @given(raw_sequence=...)
        def test_encode_sequence(self, cairo_run, raw_sequence: Tuple[Bytes, ...]):
            assert encode_sequence(raw_sequence) == cairo_run(
                "encode_sequence", raw_sequence
            )

        @given(raw_bytes=...)
        def test_rlp_hash(self, cairo_run, raw_bytes: Bytes):
            assert rlp_hash(raw_bytes) == cairo_run("rlp_hash", raw_bytes)

    class TestDecode:
        @given(raw_data=st.recursive(st.binary(), st.tuples))
        def test_decode(self, cairo_run, raw_data):
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

        @given(raw_data=st.recursive(st.binary(), st.tuples))
        def test_decode_to_sequence(self, cairo_run, raw_data):
            assume(isinstance(raw_data, tuple))
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

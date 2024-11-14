from hypothesis import given

from ethereum.base_types import Bytes
from ethereum.rlp import (
    decode_to_bytes,
    encode_bytes,
    encode_sequence,
    get_joined_encodings,
    rlp_hash,
)


class TestRlp:
    @given(raw_bytes=...)
    def test_encode_bytes(self, cairo_run, raw_bytes: Bytes):
        assert encode_bytes(raw_bytes) == cairo_run("encode_bytes", raw_bytes)

    @given(raw_sequence=...)
    def test_get_joined_encodings(self, cairo_run, raw_sequence: tuple[Bytes]):
        assert get_joined_encodings(raw_sequence) == cairo_run(
            "get_joined_encodings", raw_sequence
        )

    @given(raw_sequence=...)
    def test_encode_sequence(self, cairo_run, raw_sequence: tuple[Bytes]):
        assert encode_sequence(raw_sequence) == cairo_run(
            "encode_sequence", raw_sequence
        )

    @given(raw_bytes=...)
    def test_rlp_hash(self, cairo_run, raw_bytes: Bytes):
        assert rlp_hash(raw_bytes) == cairo_run("rlp_hash", raw_bytes)

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

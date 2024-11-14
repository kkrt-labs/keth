import hypothesis.strategies as st
from hypothesis import given

from ethereum.rlp import (
    decode_to_bytes,
    encode_bytes,
    encode_sequence,
    get_joined_encodings,
    rlp_hash,
)


class TestRlp:
    @given(raw_bytes=st.binary())
    def test_encode_bytes(self, cairo_run, raw_bytes):
        assert encode_bytes(raw_bytes) == cairo_run(
            "test_encode_bytes", raw_bytes=raw_bytes
        )

    @given(raw_sequence=st.tuples(st.binary()))
    def test_get_joined_encodings(self, cairo_run, raw_sequence):
        assert get_joined_encodings(raw_sequence) == cairo_run(
            "test_get_joined_encodings", raw_sequence=raw_sequence
        )

    @given(raw_sequence=st.tuples(st.binary()))
    def test_encode_sequence(self, cairo_run, raw_sequence):
        assert encode_sequence(raw_sequence) == cairo_run(
            "test_encode_sequence", raw_sequence=raw_sequence
        )

    @given(raw_bytes=st.binary())
    def test_rlp_hash(self, cairo_run, raw_bytes):
        assert rlp_hash(raw_bytes) == cairo_run("test_rlp_hash", raw_bytes=raw_bytes)

    @given(raw_bytes=st.binary())
    def test_decode_to_bytes(self, cairo_run, raw_bytes):
        encoded_bytes = encode_bytes(raw_bytes)
        assert decode_to_bytes(encoded_bytes) == cairo_run(
            "test_decode_to_bytes", encoded_bytes=encoded_bytes
        )

    @given(encoded_bytes=st.binary())
    def test_decode_to_bytes_should_raise(self, cairo_run, encoded_bytes):
        """
        The cairo implementation of decode_to_bytes raises more often than the
        eth-rlp implementation because this latter accepts negative lengths.
        See https://github.com/ethereum/execution-specs/issues/1035
        """
        decoded_bytes = None
        try:
            decoded_bytes = cairo_run(
                "test_decode_to_bytes", encoded_bytes=encoded_bytes
            )
        except Exception:
            pass
        if decoded_bytes is not None:
            assert decoded_bytes == decode_to_bytes(encoded_bytes)

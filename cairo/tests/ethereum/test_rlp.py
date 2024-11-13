import hypothesis.strategies as st
from hypothesis import given

from ethereum.rlp import encode_bytes, get_joined_encodings


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

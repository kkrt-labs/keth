import hypothesis.strategies as st
from hypothesis import given

from ethereum.rlp import encode_bytes


class TestRlp:
    @given(raw_bytes=st.binary())
    def test_encode_bytes(self, cairo_run, raw_bytes):
        assert encode_bytes(raw_bytes) == cairo_run(
            "test_encode_bytes", raw_bytes=raw_bytes
        )

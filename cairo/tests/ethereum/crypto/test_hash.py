from ethereum.crypto.hash import keccak256
from ethereum_types.bytes import Bytes
from hypothesis import given
from hypothesis import strategies as st


class TestHash:

    class TestKeccak256:
        @given(buffer=st.binary(max_size=1000).map(Bytes))
        def test_keccak256(self, cairo_run, buffer: Bytes):
            assert keccak256(buffer) == cairo_run("keccak256", [], buffer)

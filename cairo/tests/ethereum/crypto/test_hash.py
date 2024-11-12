import hypothesis.strategies as st
from hypothesis import given

from ethereum.crypto.hash import keccak256


class TestHash:

    class TestKeccak256:
        @given(buffer=st.binary(min_size=0, max_size=1000))
        def test_keccak256(self, cairo_run, buffer):
            assert keccak256(buffer) == cairo_run("test_keccak256", buffer=buffer)

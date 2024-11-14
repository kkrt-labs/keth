from hypothesis import assume, given

from ethereum.base_types import Bytes
from ethereum.crypto.hash import keccak256


class TestHash:

    class TestKeccak256:
        @given(buffer=...)
        def test_keccak256(self, cairo_run, buffer: Bytes):
            assume(len(buffer) <= 1000)
            assert keccak256(buffer) == cairo_run("keccak256", buffer=buffer)

import hashlib
from typing import Tuple

from ethereum_types.bytes import Bytes, Bytes20, Bytes32
from hypothesis import given
from hypothesis import strategies as st

from tests.utils.hash_utils import TupleBytes32__hash__


class TestBytes:
    # Force generating a large buffer to test the blake2s implementation - hypothesis shrinks towards small buffers.
    # @given(buffer=st.one_of(st.binary(min_size=0, max_size=500).map(Bytes), st.binary(min_size=500, max_size=1000).map(Bytes)))
    @given(buffer=st.binary(min_size=61, max_size=64).map(Bytes))
    def test_Bytes__hash__(self, cairo_run, buffer: Bytes):
        assert hashlib.blake2s(buffer).digest() == cairo_run("Bytes__hash__", buffer)


class TestBytes20:
    @given(buffer=...)
    def test_Bytes20__hash__(self, cairo_run, buffer: Bytes20):
        assert hashlib.blake2s(buffer).digest() == cairo_run("Bytes20__hash__", buffer)


class TestBytes32:
    @given(buffer=...)
    def test_Bytes32__hash__(self, cairo_run, buffer: Bytes32):
        assert hashlib.blake2s(buffer).digest() == cairo_run("Bytes32__hash__", buffer)


class TestTupleBytes32:
    @given(buffer=...)
    def test_TupleBytes32__hash__(self, cairo_run, buffer: Tuple[Bytes32, ...]):
        assert TupleBytes32__hash__(buffer) == cairo_run("TupleBytes32__hash__", buffer)

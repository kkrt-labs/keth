import hashlib

from ethereum.crypto.hash import keccak256
from ethereum_types.bytes import Bytes
from hypothesis import given
from hypothesis import strategies as st


class TestHash:

    class TestKeccak256:
        @given(buffer=st.binary(max_size=1000).map(Bytes))
        def test_keccak256(self, cairo_run, buffer: Bytes):
            assert keccak256(buffer) == cairo_run("keccak256", buffer)

    class TestBlake2s:
        @given(buffer=st.binary(max_size=1000).map(Bytes))
        def test_blake2s_bytes(self, cairo_run, buffer: Bytes):
            assert hashlib.blake2s(buffer).digest() == cairo_run(
                "blake2s_bytes", buffer
            )

    class TestHashWith:
        @given(
            buffer=st.binary(max_size=1000).map(Bytes),
            hash_function_name=st.sampled_from(["keccak256", "blake2s"]),
        )
        def test_hash_with(self, cairo_run, buffer: Bytes, hash_function_name: str):
            if hash_function_name == "keccak256":
                assert keccak256(buffer) == cairo_run(
                    "hash_with", buffer, hash_function_name
                )
            elif hash_function_name == "blake2s":
                assert hashlib.blake2s(buffer).digest() == cairo_run(
                    "hash_with", buffer, hash_function_name
                )

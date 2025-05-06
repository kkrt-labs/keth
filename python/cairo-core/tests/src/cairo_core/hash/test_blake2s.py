import hashlib
from typing import List

from hypothesis import given
from hypothesis import strategies as st

from tests.utils.strategies import positive_felt


class TestBlake2s:
    @given(felt_input=st.lists(positive_felt, min_size=1, max_size=31))
    def test_blake2s_truncated(self, cairo_run, felt_input: List[int]):
        buffer = b"".join(
            input_felt.to_bytes(32, "little") for input_felt in felt_input
        )
        # The input is an array of bytes4 values
        cairo_input = [
            int.from_bytes(buffer[i : i + 4], "little")
            for i in range(0, len(buffer), 4)
        ]
        assert hashlib.blake2s(buffer).digest()[:31] == cairo_run(
            "blake2s_truncated", cairo_input, len(felt_input) * 32
        ).to_bytes(31, "little")

    @given(felt_input=st.lists(positive_felt, min_size=1, max_size=31))
    def test_blake2s_hash_many(self, cairo_run, felt_input: List[int]):
        buffer = b"".join(
            input_felt.to_bytes(32, "little") for input_felt in felt_input
        )
        expected_hash_truncated = int.from_bytes(
            hashlib.blake2s(buffer).digest()[:31], "little"
        )
        assert expected_hash_truncated == cairo_run(
            "blake2s_hash_many", len(felt_input), felt_input
        )

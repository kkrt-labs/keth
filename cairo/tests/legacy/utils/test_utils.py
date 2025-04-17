from math import ceil

from hypothesis import given, settings
from hypothesis import strategies as st


@given(word=st.integers(min_value=0, max_value=2**256 - 1))
@settings(max_examples=20)
def test_bytes_to_uint256(cairo_run, word):
    output = cairo_run(
        "test__bytes_to_uint256",
        word=int.to_bytes(word, ceil(word.bit_length() / 8), byteorder="big"),
    )
    assert output["low"] + output["high"] * 2**128 == word

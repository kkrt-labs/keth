from math import ceil

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

pytestmark = pytest.mark.python_vm


@given(word=st.integers(min_value=0, max_value=2**256 - 1))
@settings(max_examples=20)
def test_bytes_to_uint256(cairo_run, word):
    output = cairo_run(
        "test__bytes_to_uint256",
        word=int.to_bytes(word, ceil(word.bit_length() / 8), byteorder="big"),
    )
    assert output["low"] + output["high"] * 2**128 == word


@given(word=st.integers(min_value=0, max_value=2**128 - 1))
def test_should_return_bytes_used_in_128_word(cairo_run, word):
    bytes_length = (word.bit_length() + 7) // 8
    assert bytes_length == cairo_run("test__bytes_used_128", word=word)

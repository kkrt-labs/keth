from math import ceil

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from cairo_addons.testing.errors import cairo_error

pytestmark = pytest.mark.python_vm


@pytest.mark.parametrize(
    "test_case,data,expected",
    [
        (
            "test__bytes4_array_to_bytes",
            [
                0x68656C6C,
                0x6F20776F,
                0x726C6400,
            ],
            [
                0x68,
                0x65,
                0x6C,
                0x6C,
                0x6F,
                0x20,
                0x77,
                0x6F,
                0x72,
                0x6C,
                0x64,
                0x00,
            ],
        ),
        (
            "test__bytes_to_bytes4_array",
            [
                0x68,
                0x65,
                0x6C,
                0x6C,
                0x6F,
                0x20,
                0x77,
                0x6F,
                0x72,
                0x6C,
                0x64,
                0x00,
            ],
            [
                0x68656C6C,
                0x6F20776F,
                0x726C6400,
            ],
        ),
    ],
)
def test_utils(cairo_run, test_case, data, expected):
    cairo_run(test_case, data=data, expected=expected)


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


class TestSplitWord:
    @given(value=st.integers(min_value=0, max_value=2**248 - 1))
    def test_should_split_word(self, cairo_run, value):
        length = (value.bit_length() + 7) // 8
        output = cairo_run("test__split_word", value=value, length=length)
        assert bytes(output) == (
            value.to_bytes(byteorder="big", length=length) if value != 0 else b""
        )

    @given(value=st.integers(min_value=1, max_value=2**248 - 1))
    def test_should_raise_when_length_is_too_short_split_word(self, cairo_run, value):
        length = (value.bit_length() + 7) // 8
        with cairo_error("value not empty"):
            cairo_run("test__split_word", value=value, length=length - 1)

    @given(
        value=st.integers(min_value=0, max_value=2**248 - 1),
        length=st.integers(min_value=32),
    )
    def test_should_raise_when_len_ge_32_split_word(self, cairo_run, value, length):
        with cairo_error("len must be < 32"):
            cairo_run("test__split_word", value=value, length=length)

    @given(value=st.integers(min_value=0, max_value=2**248 - 1))
    def test_should_split_word_little(self, cairo_run, value):
        length = (value.bit_length() + 7) // 8
        output = cairo_run("test__split_word_little", value=value, length=length)
        assert bytes(output) == (
            value.to_bytes(byteorder="little", length=length) if value != 0 else b""
        )

    @given(value=st.integers(min_value=1, max_value=2**248 - 1))
    def test_should_raise_when_len_is_too_small_split_word_little(
        self, cairo_run, value
    ):
        length = (value.bit_length() + 7) // 8
        with cairo_error("value not empty"):
            cairo_run("test__split_word_little", value=value, length=length - 1)

    @given(
        value=st.integers(min_value=0, max_value=2**248 - 1),
        length=st.integers(min_value=32),
    )
    def test_should_raise_when_len_ge_32_split_word_little(
        self, cairo_run, value, length
    ):
        with cairo_error("len must be < 32"):
            cairo_run("test__split_word_little", value=value, length=length)

from math import ceil

import pytest
from ethereum_types.bytes import Bytes
from ethereum_types.numeric import Uint
from hypothesis import example, given, settings
from hypothesis import strategies as st

from ethereum.cancun.vm.runtime import get_valid_jump_destinations
from tests.utils.errors import cairo_error
from tests.utils.solidity import get_contract

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


@pytest.mark.parametrize(
    "bytes,expected",
    [
        (b"", [0, 0]),  # An empty field
        (
            b"\x01" * 20,
            [1, 0x0101010101010101010101010101010101010101],
        ),  # An address of 20 bytes
    ],
)
def test_should_parse_destination_from_bytes(cairo_run, bytes, expected):
    result = cairo_run("test__try_parse_destination_from_bytes", bytes=list(bytes))
    assert result == expected


@given(bytes_array=st.binary(min_size=1, max_size=32).filter(lambda x: len(x) != 20))
def test_should_panic_incorrect_address_encoding(cairo_run, bytes_array):
    with cairo_error(message=f"Bytes has length {len(bytes_array)}, expected 0 or 20"):
        cairo_run("test__try_parse_destination_from_bytes", bytes=list(bytes_array))


class TestInitializeJumpdests:
    @given(bytecode=...)
    @example(bytecode=get_contract("Counter", "Counter").bytecode_runtime)
    def test_should_return_same_as_execution_specs(self, cairo_run, bytecode: Bytes):
        output = cairo_run("test__initialize_jumpdests", bytecode=bytecode)
        assert set(
            map(Uint, output if isinstance(output, list) else [output])
        ) == get_valid_jump_destinations(bytecode)


class TestFinalizeJumpdests:
    @given(bytecode=...)
    @example(bytecode=get_contract("Counter", "Counter").bytecode_runtime)
    def test_should_pass(self, cairo_run, bytecode: Bytes):
        cairo_run(
            "test__finalize_jumpdests",
            bytecode=list(bytecode),
            valid_jumpdests=get_valid_jump_destinations(bytecode),
        )


class TestAssertValidJumpdest:
    @pytest.mark.parametrize(
        "jumpdest",
        get_valid_jump_destinations(
            get_contract("Counter", "Counter").bytecode_runtime
        ),
    )
    def test_should_pass_on_valid_jumpdest(self, cairo_run, jumpdest):
        cairo_run(
            "test__assert_valid_jumpdest",
            bytecode=list(get_contract("Counter", "Counter").bytecode_runtime),
            valid_jumpdest=[int(jumpdest), 1, 1],
        )

    def test_should_raise_if_jumpdest_but_false(self, cairo_run):
        with cairo_error("assert_valid_jumpdest: invalid jumpdest"):
            cairo_run(
                "test__assert_valid_jumpdest", bytecode=[0x5B], valid_jumpdest=[0, 0, 0]
            )

    @pytest.mark.parametrize("push", list(range(0x60, 0x80)))
    def test_should_raise_if_jumpdest_is_push_arg(self, cairo_run, push):
        with cairo_error("assert_valid_jumpdest: invalid jumpdest"):
            cairo_run(
                "test__assert_valid_jumpdest",
                bytecode=[push] + (push - 0x5F) * [0x5B],
                valid_jumpdest=[push - 0x5F, 1, 1],
            )


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

from typing import List

from ethereum.exceptions import EthereumException
from ethereum.prague.requests import (
    AMOUNT_OFFSET,
    AMOUNT_SIZE,
    DEPOSIT_EVENT_LENGTH,
    INDEX_OFFSET,
    INDEX_SIZE,
    PUBKEY_OFFSET,
    PUBKEY_SIZE,
    SIGNATURE_OFFSET,
    SIGNATURE_SIZE,
    WITHDRAWAL_CREDENTIALS_OFFSET,
    WITHDRAWAL_CREDENTIALS_SIZE,
    compute_requests_hash,
    extract_deposit_data,
    parse_deposit_requests,
)
from ethereum.prague.vm import BlockOutput
from ethereum_types.bytes import Bytes
from hypothesis import given
from hypothesis import strategies as st

from cairo_addons.testing.errors import strict_raises
from tests.utils.strategies import small_bytes

PUBKEY_OFFSET = int(PUBKEY_OFFSET)
WITHDRAWAL_CREDENTIALS_OFFSET = int(WITHDRAWAL_CREDENTIALS_OFFSET)
AMOUNT_OFFSET = int(AMOUNT_OFFSET)
SIGNATURE_OFFSET = int(SIGNATURE_OFFSET)
INDEX_OFFSET = int(INDEX_OFFSET)

PUBKEY_SIZE = int(PUBKEY_SIZE)
WITHDRAWAL_CREDENTIALS_SIZE = int(WITHDRAWAL_CREDENTIALS_SIZE)
AMOUNT_SIZE = int(AMOUNT_SIZE)
SIGNATURE_SIZE = int(SIGNATURE_SIZE)
INDEX_SIZE = int(INDEX_SIZE)


# Strategy for generating valid deposit event data
@st.composite
def valid_deposit_data_strategy(draw):
    """Generate valid deposit event data for testing."""
    data = bytearray(DEPOSIT_EVENT_LENGTH)

    # Set offsets (big-endian, 32 bytes each)
    data[28:32] = PUBKEY_OFFSET.to_bytes(4, "big")
    data[60:64] = WITHDRAWAL_CREDENTIALS_OFFSET.to_bytes(4, "big")
    data[92:96] = AMOUNT_OFFSET.to_bytes(4, "big")
    data[124:128] = SIGNATURE_OFFSET.to_bytes(4, "big")
    data[156:160] = INDEX_OFFSET.to_bytes(4, "big")

    # Set sizes at their respective offsets
    data[PUBKEY_OFFSET + 28 : PUBKEY_OFFSET + 32] = PUBKEY_SIZE.to_bytes(4, "big")
    data[WITHDRAWAL_CREDENTIALS_OFFSET + 28 : WITHDRAWAL_CREDENTIALS_OFFSET + 32] = (
        WITHDRAWAL_CREDENTIALS_SIZE.to_bytes(4, "big")
    )
    data[AMOUNT_OFFSET + 28 : AMOUNT_OFFSET + 32] = AMOUNT_SIZE.to_bytes(4, "big")
    data[SIGNATURE_OFFSET + 28 : SIGNATURE_OFFSET + 32] = SIGNATURE_SIZE.to_bytes(
        4, "big"
    )
    data[INDEX_OFFSET + 28 : INDEX_OFFSET + 32] = INDEX_SIZE.to_bytes(4, "big")

    # Add random data for the actual fields
    pubkey_data = draw(st.binary(min_size=PUBKEY_SIZE, max_size=PUBKEY_SIZE))
    data[PUBKEY_OFFSET + 32 : PUBKEY_OFFSET + 32 + PUBKEY_SIZE] = pubkey_data

    withdrawal_credentials_data = draw(
        st.binary(
            min_size=WITHDRAWAL_CREDENTIALS_SIZE, max_size=WITHDRAWAL_CREDENTIALS_SIZE
        )
    )
    data[
        WITHDRAWAL_CREDENTIALS_OFFSET
        + 32 : WITHDRAWAL_CREDENTIALS_OFFSET
        + 32
        + WITHDRAWAL_CREDENTIALS_SIZE
    ] = withdrawal_credentials_data

    amount_data = draw(st.binary(min_size=AMOUNT_SIZE, max_size=AMOUNT_SIZE))
    data[AMOUNT_OFFSET + 32 : AMOUNT_OFFSET + 32 + AMOUNT_SIZE] = amount_data

    signature_data = draw(st.binary(min_size=SIGNATURE_SIZE, max_size=SIGNATURE_SIZE))
    data[SIGNATURE_OFFSET + 32 : SIGNATURE_OFFSET + 32 + SIGNATURE_SIZE] = (
        signature_data
    )

    index_data = draw(st.binary(min_size=INDEX_SIZE, max_size=INDEX_SIZE))
    data[INDEX_OFFSET + 32 : INDEX_OFFSET + 32 + INDEX_SIZE] = index_data

    return Bytes(data)


# Strategy for generating invalid deposit event data
@st.composite
def invalid_deposit_data_strategy(draw):
    """Generate invalid deposit event data for testing."""
    invalid_type = draw(
        st.sampled_from(
            [
                "wrong_length",
                "wrong_pubkey_offset",
                "wrong_withdrawal_credentials_offset",
                "wrong_amount_offset",
                "wrong_signature_offset",
                "wrong_index_offset",
                "wrong_pubkey_size",
                "wrong_withdrawal_credentials_size",
                "wrong_amount_size",
                "wrong_signature_size",
                "wrong_index_size",
            ]
        )
    )

    if invalid_type == "wrong_length":
        # Generate data with wrong length
        wrong_length = draw(
            st.integers(min_value=1, max_value=1000).filter(
                lambda x: x != DEPOSIT_EVENT_LENGTH
            )
        )
        return Bytes(draw(st.binary(min_size=wrong_length, max_size=wrong_length)))

    # Start with valid data structure
    data = bytearray(DEPOSIT_EVENT_LENGTH)

    # Set correct offsets initially
    data[28:32] = PUBKEY_OFFSET.to_bytes(4, "big")
    data[60:64] = WITHDRAWAL_CREDENTIALS_OFFSET.to_bytes(4, "big")
    data[92:96] = AMOUNT_OFFSET.to_bytes(4, "big")
    data[124:128] = SIGNATURE_OFFSET.to_bytes(4, "big")
    data[156:160] = INDEX_OFFSET.to_bytes(4, "big")

    # Set correct sizes initially
    data[PUBKEY_OFFSET + 28 : PUBKEY_OFFSET + 32] = PUBKEY_SIZE.to_bytes(4, "big")
    data[WITHDRAWAL_CREDENTIALS_OFFSET + 28 : WITHDRAWAL_CREDENTIALS_OFFSET + 32] = (
        WITHDRAWAL_CREDENTIALS_SIZE.to_bytes(4, "big")
    )
    data[AMOUNT_OFFSET + 28 : AMOUNT_OFFSET + 32] = AMOUNT_SIZE.to_bytes(4, "big")
    data[SIGNATURE_OFFSET + 28 : SIGNATURE_OFFSET + 32] = SIGNATURE_SIZE.to_bytes(
        4, "big"
    )
    data[INDEX_OFFSET + 28 : INDEX_OFFSET + 32] = INDEX_SIZE.to_bytes(4, "big")

    # Now corrupt one field based on invalid_type
    if invalid_type == "wrong_pubkey_offset":
        wrong_offset = draw(
            st.integers(min_value=0, max_value=1000).filter(
                lambda x: x != PUBKEY_OFFSET
            )
        )
        data[28:32] = wrong_offset.to_bytes(4, "big")
    elif invalid_type == "wrong_withdrawal_credentials_offset":
        wrong_offset = draw(
            st.integers(min_value=0, max_value=1000).filter(
                lambda x: x != WITHDRAWAL_CREDENTIALS_OFFSET
            )
        )
        data[60:64] = wrong_offset.to_bytes(4, "big")
    elif invalid_type == "wrong_amount_offset":
        wrong_offset = draw(
            st.integers(min_value=0, max_value=1000).filter(
                lambda x: x != AMOUNT_OFFSET
            )
        )
        data[92:96] = wrong_offset.to_bytes(4, "big")
    elif invalid_type == "wrong_signature_offset":
        wrong_offset = draw(
            st.integers(min_value=0, max_value=1000).filter(
                lambda x: x != SIGNATURE_OFFSET
            )
        )
        data[124:128] = wrong_offset.to_bytes(4, "big")
    elif invalid_type == "wrong_index_offset":
        wrong_offset = draw(
            st.integers(min_value=0, max_value=1000).filter(lambda x: x != INDEX_OFFSET)
        )
        data[156:160] = wrong_offset.to_bytes(4, "big")
    elif invalid_type == "wrong_pubkey_size":
        wrong_size = draw(
            st.integers(min_value=0, max_value=1000).filter(lambda x: x != PUBKEY_SIZE)
        )
        data[PUBKEY_OFFSET + 28 : PUBKEY_OFFSET + 32] = wrong_size.to_bytes(4, "big")
    elif invalid_type == "wrong_withdrawal_credentials_size":
        wrong_size = draw(
            st.integers(min_value=0, max_value=1000).filter(
                lambda x: x != WITHDRAWAL_CREDENTIALS_SIZE
            )
        )
        data[
            WITHDRAWAL_CREDENTIALS_OFFSET + 28 : WITHDRAWAL_CREDENTIALS_OFFSET + 32
        ] = wrong_size.to_bytes(4, "big")
    elif invalid_type == "wrong_amount_size":
        wrong_size = draw(
            st.integers(min_value=0, max_value=1000).filter(lambda x: x != AMOUNT_SIZE)
        )
        data[AMOUNT_OFFSET + 28 : AMOUNT_OFFSET + 32] = wrong_size.to_bytes(4, "big")
    elif invalid_type == "wrong_signature_size":
        wrong_size = draw(
            st.integers(min_value=0, max_value=1000).filter(
                lambda x: x != SIGNATURE_SIZE
            )
        )
        data[SIGNATURE_OFFSET + 28 : SIGNATURE_OFFSET + 32] = wrong_size.to_bytes(
            4, "big"
        )
    elif invalid_type == "wrong_index_size":
        wrong_size = draw(
            st.integers(min_value=0, max_value=1000).filter(lambda x: x != INDEX_SIZE)
        )
        data[INDEX_OFFSET + 28 : INDEX_OFFSET + 32] = wrong_size.to_bytes(4, "big")

    return Bytes(data)


# Strategy for generating lists of requests
requests_strategy = st.lists(small_bytes.map(Bytes), min_size=0, max_size=10)


class TestExtractDepositData:
    """Test the extract_deposit_data function using property-based testing."""

    @given(data=valid_deposit_data_strategy())
    def test_extract_deposit_data_valid(self, cairo_run, data: Bytes):
        try:
            cairo_result = cairo_run("extract_deposit_data", data)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                extract_deposit_data(data)
            return

        python_result = extract_deposit_data(data)
        assert cairo_result == python_result

    @given(data=invalid_deposit_data_strategy())
    def test_extract_deposit_data_invalid(self, cairo_run, data: Bytes):
        try:
            cairo_result = cairo_run("extract_deposit_data", data)
            python_result = extract_deposit_data(data)
            assert cairo_result == python_result
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                extract_deposit_data(data)


class TestParseDepositRequests:

    @given(block_output=...)
    def test_parse_deposit_requests(self, cairo_run, block_output: BlockOutput):
        try:
            cairo_block_output, cairo_result = cairo_run("parse_deposit_requests", block_output)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                parse_deposit_requests(block_output)
            return

        python_result = parse_deposit_requests(block_output)
        assert cairo_block_output == block_output
        assert cairo_result == python_result


class TestComputeRequestsHash:
    @given(requests=requests_strategy)
    def test_compute_requests_hash(self, cairo_run, requests: List[Bytes]):
        try:
            cairo_result = cairo_run("compute_requests_hash", requests, len(requests))
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                compute_requests_hash(requests)
            return

        python_result = compute_requests_hash(requests)
        assert cairo_result == python_result

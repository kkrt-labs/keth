import pytest
from hypothesis import given
from hypothesis.strategies import binary, lists, recursive
from rlp import codec, decode, encode
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

from tests.utils.constants import TRANSACTIONS
from tests.utils.errors import cairo_error
from tests.utils.helpers import rlp_encode_signed_data


class TestRLP:
    class TestDecodeType:
        @given(data=lists(binary()) | binary())
        def test_should_match_prefix_reference_implementation(self, cairo_run, data):
            encoded_data = encode(data)

            [
                prefix,
                rlp_type,
                expected_len,
                expected_offset,
            ] = codec.consume_length_prefix(encoded_data, 0)
            expected_type = 0 if rlp_type is bytes else 1

            output = cairo_run("test__decode_type", data=list(encoded_data))

            assert output == [expected_type, expected_offset, expected_len]

    class TestDecodeRaw:
        def test_should_raise_when_parsed_len_greater_than_data(self, cairo_run):
            with cairo_error("RLP data too short for declared length"):
                cairo_run("test__decode_raw", data=[0xB8, 0x01])

        @given(data=lists(binary(min_size=2), min_size=2) | binary(min_size=2))
        def test_should_raise_when_malicious_prover_fills_data(self, cairo_run, data):
            with cairo_error("RLP data too short for declared length"):
                cairo_run(
                    "test__decode_raw",
                    data_len=len(encode(data)) - 1,
                    data=list(encode(data)),
                )

        def test_should_raise_when_decoded_params_overflow(self, cairo_run):
            size = bytes.fromhex(f"{DEFAULT_PRIME - 1:064x}")
            data = [len(size) + 0xF7] + list(size)
            with cairo_error("RLP data too short for declared length"):
                cairo_run("test__decode_raw", data=data)

    class TestDecode:
        @given(data=recursive(binary(), lists))
        def test_should_match_decode_reference_implementation(self, cairo_run, data):
            encoded_data = encode(data)

            items = cairo_run("test__decode", data=list(encoded_data))
            assert items[0] == decode(encoded_data)

        @given(
            data=recursive(binary(), lists),
            extra_data=binary(min_size=1, max_size=255),
        )
        def test_raise_when_data_contains_extra_bytes(
            self, cairo_run, data, extra_data
        ):
            encoded_data = encode(data)

            with cairo_error(
                f"RLP string ends with {len(extra_data)} superfluous bytes"
            ):
                cairo_run("test__decode", data=list(encoded_data + extra_data))

        @pytest.mark.parametrize("transaction", TRANSACTIONS)
        def test_should_decode_all_tx_types(self, cairo_run, transaction):
            encoded_unsigned_tx = rlp_encode_signed_data(transaction)
            if "type" in transaction:
                # remove the type info from the encoded RLP
                # create bytearray from bytes list and remove the first byte
                rlp_encoding = bytes(encoded_unsigned_tx[1:])
            else:
                rlp_encoding = encoded_unsigned_tx

            items = cairo_run("test__decode", data=list(rlp_encoding))
            assert items[0] == decode(rlp_encoding)

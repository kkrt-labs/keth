import pytest
from ethereum_types.numeric import U256
from hypothesis import given
from hypothesis import strategies as st

from ethereum.crypto.elliptic_curve import SECP256K1N, secp256k1_recover
from ethereum.crypto.hash import Hash32, keccak256
from ethereum.utils.byte import left_pad_zero_bytes
from tests.utils.helpers import ec_sign, generate_random_private_key


def ecrecover(data):
    message_hash_bytes = data[0:32]
    message_hash = Hash32(message_hash_bytes)
    v = U256.from_be_bytes(data[32:64])
    r = U256.from_be_bytes(data[64:96])
    s = U256.from_be_bytes(data[96:128])

    if v != U256(27) and v != U256(28):
        return []
    if U256(0) >= r or r >= SECP256K1N:
        return []
    if U256(0) >= s or s >= SECP256K1N:
        return []

    try:
        public_key = secp256k1_recover(r, s, v - U256(27), message_hash)
    except ValueError:
        # unable to extract public key
        return []

    address = keccak256(public_key)[12:32]
    padded_address = left_pad_zero_bytes(address, 32)
    return padded_address, public_key


@pytest.mark.EC_RECOVER
class TestEcRecover:
    @given(message=st.binary(min_size=1, max_size=1000))
    def test_valid_signature(self, message, cairo_run):
        """Test with valid signatures generated from random messages."""
        private_key = generate_random_private_key()
        msg_hash = keccak256(message)
        (v, r, s) = ec_sign(msg_hash, private_key)

        input_data = [*msg_hash, *v.to_bytes(32, "big"), *r, *s]

        padded_address, _ = ecrecover(input_data)
        output = cairo_run("test__ec_recover", input=input_data)
        assert bytes(output) == bytes(padded_address)

    @given(input_length=st.integers(min_value=0, max_value=127))
    def test_invalid_input_length(self, input_length, cairo_run):
        """Test with various invalid input lengths."""
        input_data = [0] * input_length
        output = cairo_run("test__ec_recover", input=input_data)
        assert output == []

    @given(
        v=st.integers(min_value=0, max_value=26) | st.integers(min_value=29),
        msg=st.binary(min_size=32, max_size=32),
        r=st.integers(min_value=1, max_value=int(SECP256K1N) - 1),
        s=st.integers(min_value=1, max_value=int(SECP256K1N) - 1),
    )
    def test_invalid_v(self, v, msg, r, s, cairo_run):
        """Test with invalid v values."""
        input_data = [
            *msg,
            *v.to_bytes(32, "big"),
            *r.to_bytes(32, "big"),
            *s.to_bytes(32, "big"),
        ]
        py_result = ecrecover(input_data)
        output = cairo_run("test__ec_recover", input=input_data)
        assert output == py_result

    @given(
        v=st.integers(min_value=27, max_value=28),
        msg=st.binary(min_size=32, max_size=32),
        r=st.integers(min_value=0, max_value=2**256 - 1),
        s=st.integers(min_value=0, max_value=2**256 - 1),
    )
    def test_parameter_boundaries(self, cairo_run, v, msg, r, s):
        """Test `r` and `s` parameter validation including boundary conditions."""
        input_data = [
            *msg,
            *v.to_bytes(32, "big"),
            *r.to_bytes(32, "big"),
            *s.to_bytes(32, "big"),
        ]

        py_result = ecrecover(input_data)
        cairo_result = cairo_run("test__ec_recover", input=input_data)

        if len(py_result) == 0:
            assert cairo_result == py_result
        else:
            py_address, _ = py_result
            assert bytes(cairo_result) == bytes(py_address)

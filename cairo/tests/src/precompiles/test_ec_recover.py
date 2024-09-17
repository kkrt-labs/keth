import pytest
from ethereum.base_types import U256
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

    if v != 27 and v != 28:
        return
    if 0 >= r or r >= SECP256K1N:
        return
    if 0 >= s or s >= SECP256K1N:
        return

    try:
        public_key = secp256k1_recover(r, s, v - 27, message_hash)
    except ValueError:
        # unable to extract public key
        return

    address = keccak256(public_key)[12:32]
    padded_address = left_pad_zero_bytes(address, 32)
    return padded_address, public_key


@pytest.mark.xfail(reason="Cairo1Helpers migration")
@pytest.mark.EC_RECOVER
class TestEcRecover:
    def test_should_return_evm_address_in_bytes32(self, cairo_run):
        private_key = generate_random_private_key()
        msg = keccak256(b"test message")
        (v, r, s) = ec_sign(msg, private_key)

        input_data = [
            *msg,
            *v.to_bytes(32, "big"),
            *r,
            *s,
        ]

        padded_address, _ = ecrecover(input_data)

        [output] = cairo_run("test__ec_recover", input=input_data)

        assert bytes(output) == bytes(padded_address)

    def test_should_fail_when_input_len_is_not_128(self, cairo_run):
        [output] = cairo_run("test__ec_recover", input=[])
        assert output == []

    def test_should_fail_when_recovery_identifier_is_neither_27_nor_28(self, cairo_run):
        private_key = generate_random_private_key()
        msg = keccak256(b"test message")
        (_, r, s) = ec_sign(msg, private_key)
        v = 1
        input_data = [
            *msg,
            *v.to_bytes(32, "big"),
            *r,
            *s,
        ]
        [output] = cairo_run("test__ec_recover", input=input_data)
        assert output == []

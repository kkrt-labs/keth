import pytest
from eth_keys.datatypes import PrivateKey
from hypothesis import assume, given
from hypothesis.strategies import integers
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

from ethereum.base_types import U256, Bytes32
from ethereum.crypto.elliptic_curve import SECP256K1N
from tests.utils.errors import cairo_error
from tests.utils.strategies import felt


class TestSignature:
    class TestPublicKeyPointToEthAddress:
        @given(private_key=...)
        def test__public_key_point_to_eth_address(
            self, cairo_run, private_key: PrivateKey
        ):
            public_key = private_key.public_key
            public_key_bytes = public_key.to_bytes()
            x = U256.from_be_bytes(public_key_bytes[0:32])
            y = U256.from_be_bytes(public_key_bytes[32:64])

            expected_address = public_key.to_address()
            result = cairo_run(
                "test__public_key_point_to_eth_address",
                x=x,
                y=y,
            )
            assert result == int(expected_address, 16)

    class TestVerifyEthSignature:
        @given(private_key=..., message=...)
        @pytest.mark.slow
        def test__verify_eth_signature_uint256(
            self, cairo_run, private_key: PrivateKey, message: Bytes32
        ):
            signature = private_key.sign_msg_hash(message)
            eth_address = int(private_key.public_key.to_address(), 16)
            cairo_run(
                "test__verify_eth_signature_uint256",
                msg_hash=U256.from_be_bytes(message),
                r=U256(signature.r),
                s=U256(signature.s),
                y_parity=signature.v,
                eth_address=eth_address,
            )

        @given(
            msg_hash=...,
            r=...,
            s=...,
            y_parity=integers(min_value=2, max_value=DEFAULT_PRIME - 1),
            eth_address=felt,
        )
        def test_should_raise_with_invalid_y_parity(
            self, cairo_run, msg_hash: U256, r: U256, s: U256, y_parity, eth_address
        ):
            assume(r != 0 and s != 0)
            assume(r < SECP256K1N and s < SECP256K1N)
            with cairo_error("Invalid y_parity"):
                cairo_run(
                    "test__verify_eth_signature_uint256",
                    msg_hash,
                    r,
                    s,
                    y_parity,
                    eth_address,
                )

            # TODO: check non-valid cases.

    class TestTryRecoverEthAddress:
        @given(private_key=..., message=...)
        @pytest.mark.slow
        def test__try_recover_eth_address(
            self, cairo_run, private_key: PrivateKey, message: Bytes32
        ):
            signature = private_key.sign_msg_hash(message)
            expected_address = int(private_key.public_key.to_address(), 16)
            result = cairo_run(
                "test__try_recover_eth_address",
                msg_hash=U256.from_be_bytes(message),
                r=U256(signature.r),
                s=U256(signature.s),
                y_parity=signature.v,
            )
            assert result.success == 1
            assert result.address == expected_address

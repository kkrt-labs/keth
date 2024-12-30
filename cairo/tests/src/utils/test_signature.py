import pytest
from eth_keys.datatypes import PrivateKey
from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U256
from hypothesis import given, settings
from hypothesis import strategies as st
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

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
            result = cairo_run("test__public_key_point_to_eth_address", x=x, y=y)
            assert result == int(expected_address, 16)

    class TestVerifyEthSignature:
        # @pytest.mark.slow
        @settings(deadline=None)
        @given(private_key=..., message=...)
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
            r=st.integers(min_value=1, max_value=int(SECP256K1N) - 1).map(U256),
            s=st.integers(min_value=1, max_value=int(SECP256K1N) - 1).map(U256),
            y_parity=st.integers(min_value=2, max_value=DEFAULT_PRIME - 1),
            eth_address=felt,
        )
        def test_should_raise_with_invalid_y_parity(
            self, cairo_run, msg_hash: U256, r: U256, s: U256, y_parity, eth_address
        ):
            with cairo_error("Invalid y_parity"):
                cairo_run(
                    "test__verify_eth_signature_uint256",
                    msg_hash,
                    r,
                    s,
                    y_parity,
                    eth_address,
                )

        @given(
            msg_hash=...,
            r=st.one_of(
                st.just(0),
                st.integers(min_value=int(SECP256K1N), max_value=int(U256.MAX_VALUE)),
            ).map(U256),
            s=st.integers(min_value=1, max_value=int(SECP256K1N) - 1).map(U256),
            y_parity=...,
            eth_address=felt,
        )
        def test_should_raise_with_out_of_bounds_r(
            self,
            cairo_run,
            msg_hash: U256,
            r: U256,
            s: U256,
            y_parity: bool,
            eth_address,
        ):
            with cairo_error("Signature out of range."):
                cairo_run(
                    "test__verify_eth_signature_uint256",
                    msg_hash,
                    r,
                    s,
                    y_parity,
                    eth_address,
                )

        @given(
            msg_hash=...,
            r=st.integers(min_value=1, max_value=int(SECP256K1N) - 1).map(U256),
            s=st.one_of(
                st.just(0),
                st.integers(min_value=int(SECP256K1N), max_value=int(U256.MAX_VALUE)),
            ).map(U256),
            y_parity=...,
            eth_address=felt,
        )
        def test_should_raise_with_out_of_bounds_s(
            self,
            cairo_run,
            msg_hash: U256,
            r: U256,
            s: U256,
            y_parity: bool,
            eth_address,
        ):
            with cairo_error("Signature out of range."):
                cairo_run(
                    "test__verify_eth_signature_uint256",
                    msg_hash,
                    r,
                    s,
                    y_parity,
                    eth_address,
                )

    class TestTryRecoverEthAddress:
        # @pytest.mark.slow
        @settings(deadline=None)
        @given(private_key=..., message=...)
        def test__try_recover_eth_address(
            self, cairo_run, private_key: PrivateKey, message: Bytes32
        ):
            signature = private_key.sign_msg_hash(message)
            expected_address = int(private_key.public_key.to_address(), 16)
            success, address = cairo_run(
                "test__try_recover_eth_address",
                msg_hash=U256.from_be_bytes(message),
                r=U256(signature.r),
                s=U256(signature.s),
                y_parity=signature.v,
            )
            assert success == 1
            assert address == expected_address

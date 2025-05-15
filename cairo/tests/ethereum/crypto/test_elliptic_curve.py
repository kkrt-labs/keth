from eth_keys.datatypes import PrivateKey
from ethereum.prague.fork_types import Address
from ethereum.crypto.elliptic_curve import secp256k1_recover
from ethereum.crypto.hash import Hash32, keccak256
from ethereum_types.bytes import Bytes
from ethereum_types.numeric import U256
from hypothesis import given

from cairo_addons.testing.errors import strict_raises
from tests.utils.strategies import bytes64


class TestEllipticCurve:
    @given(private_key=..., message=...)
    def test_secp256k1_recover(
        self, cairo_run, private_key: PrivateKey, message: Hash32
    ):
        signature = private_key.sign_msg_hash(message)
        r = U256(signature.r)
        s = U256(signature.s)
        v = U256(signature.v)
        public_key_x, public_key_y = cairo_run(
            "secp256k1_recover",
            r=r,
            s=s,
            v=v,
            msg_hash=message,
        )

        result = secp256k1_recover(r, s, v, message)
        assert public_key_x == result[:32]
        assert public_key_y == result[32:]

    @given(private_key=..., message=..., v=...)
    def test_secp256k1_recover_should_fail_with_invalid_signature(
        self, cairo_run, private_key: PrivateKey, message: Hash32, v: U256
    ):
        signature = private_key.sign_msg_hash(message)
        r = U256(signature.r)
        s = U256(signature.s)
        try:
            cairo_run(
                "secp256k1_recover",
                r=r,
                s=s,
                v=v,
                msg_hash=message,
            )
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                secp256k1_recover(r, s, v, message)
            return

    @given(public_key=bytes64.map(Bytes))
    def test_public_key_point_to_eth_address(self, cairo_run, public_key: Bytes):
        cairo_result = cairo_run(
            "public_key_point_to_eth_address",
            public_key_x=public_key[:32],
            public_key_y=public_key[32:],
        )

        assert cairo_result == Address(keccak256(public_key)[12:32])

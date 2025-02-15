from eth_keys.datatypes import PrivateKey
from ethereum.crypto.elliptic_curve import secp256k1_recover
from ethereum.crypto.hash import Hash32
from ethereum_types.numeric import U256
from hypothesis import given

from cairo_addons.testing.errors import strict_raises


class TestEllipticCurve:
    @given(private_key=..., message=...)
    def test_secp256k1_recover(
        self, cairo_run, private_key: PrivateKey, message: Hash32
    ):
        signature = private_key.sign_msg_hash(message)
        r = U256(signature.r)
        s = U256(signature.s)
        v = U256(signature.v)
        x, y = cairo_run(
            "secp256k1_recover_uint256_bigends",
            r=r,
            s=s,
            v=v,
            msg_hash=message,
        )

        result = secp256k1_recover(r, s, v, message)
        assert x == U256.from_be_bytes(result[0:32])
        assert y == U256.from_be_bytes(result[32:64])

    @given(private_key=..., message=..., v=...)
    def test_secp256k1_recover_should_fail_with_invalid_signature(
        self, cairo_run, private_key: PrivateKey, message: Hash32, v: U256
    ):
        signature = private_key.sign_msg_hash(message)
        r = U256(signature.r)
        s = U256(signature.s)
        try:
            cairo_run(
                "secp256k1_recover_uint256_bigends",
                r=r,
                s=s,
                v=v,
                msg_hash=message,
            )
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                secp256k1_recover(r, s, v, message)
            return

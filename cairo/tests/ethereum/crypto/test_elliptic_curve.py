import pytest
from eth_keys.datatypes import PrivateKey
from ethereum_types.numeric import U256
from hypothesis import given, reproduce_failure

from ethereum.crypto.elliptic_curve import secp256k1_recover
from ethereum.crypto.hash import Hash32

pytestmark = pytest.mark.python_vm


class TestEllipticCurve:
    @reproduce_failure("6.124.3", b"AEMAgfZDANR1")
    @given(private_key=..., message=...)
    def test_secp256k1_recover(
        self, cairo_run, private_key: PrivateKey, message: Hash32
    ):
        signature = private_key.sign_msg_hash(message)
        r = U256(signature.r)
        s = U256(signature.s)
        v = U256(signature.v)

        x, y = cairo_run(
            "secp256k1_recover",
            r=r,
            s=s,
            v=v,
            msg_hash=message,
        )
        result = secp256k1_recover(r, s, v, message)
        assert x == U256.from_be_bytes(result[0:32])
        assert y == U256.from_be_bytes(result[32:64])

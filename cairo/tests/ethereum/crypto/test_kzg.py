import pytest
from ethereum.crypto.kzg import BLS_MODULUS, bytes_to_bls_field
from ethereum_types.bytes import Bytes, Bytes32
from hypothesis import given
from hypothesis import strategies as st
from py_ecc.bls.hash import os2ip


@given(a=...)
def test_bytes_to_bls_field(cairo_run, a: Bytes32):
    assert cairo_run("bytes_to_bls_field", a) == bytes_to_bls_field(a)


@given(a=st.integers(min_value=int(BLS_MODULUS) + 1, max_value=2**256 - 1))
def test_bytes_to_bls_fail(cairo_run, a: int):
    a_bytes32 = Bytes32(a.to_bytes(32, "big"))
    with pytest.raises(AssertionError):
        bytes_to_bls_field(a_bytes32)
    with pytest.raises(AssertionError):
        cairo_run("bytes_to_bls_field", a_bytes32)


@given(a=st.binary(max_size=48).map(Bytes))
def test_os2ip(cairo_run, a: Bytes):
    assert cairo_run("os2ip", a) == os2ip(a)

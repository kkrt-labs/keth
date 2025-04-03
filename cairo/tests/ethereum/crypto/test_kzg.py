from typing import Optional

import pytest
from ethereum.crypto.kzg import BLS_MODULUS, bytes_to_bls_field
from ethereum_types.bytes import Bytes, Bytes32
from hypothesis import example, given
from hypothesis import strategies as st
from py_ecc.bls.hash import os2ip
from py_ecc.bls.point_compression import get_flags, is_point_at_infinity

from tests.utils.args_gen import U384


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


@given(z=...)
@example(z=U384(2**383 + 2**382 + 2**381))
def test_get_flags(cairo_run, z: U384):
    c_flag, b_flag, a_flag = get_flags(int(z))
    cairo_flags = cairo_run("get_flags", z)
    assert cairo_flags[0] == c_flag
    assert cairo_flags[1] == b_flag
    assert cairo_flags[2] == a_flag


@given(z1=..., z2=...)
def test_is_point_at_infinity(cairo_run, z1: U384, z2: Optional[U384]):
    assert cairo_run("is_point_at_infinity", z1, z2) == is_point_at_infinity(
        int(z1), int(z2) if z2 else None
    )

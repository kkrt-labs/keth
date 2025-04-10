from typing import Optional

import pytest
from eth_typing import BLSPubkey as BLSPubkey_py
from ethereum.crypto.kzg import (
    BLS_MODULUS,
    KZGCommitment,
    bytes_to_bls_field,
    bytes_to_kzg_commitment,
    bytes_to_kzg_proof,
    kzg_commitment_to_versioned_hash,
    validate_kzg_g1,
)
from ethereum_types.bytes import Bytes, Bytes32, Bytes48
from hypothesis import example, given
from hypothesis import strategies as st
from py_ecc.bls.ciphersuites import G2ProofOfPossession
from py_ecc.bls.constants import POW_2_381, POW_2_382, POW_2_383, POW_2_384
from py_ecc.bls.g2_primitives import pubkey_to_G1, subgroup_check
from py_ecc.bls.hash import os2ip
from py_ecc.bls.point_compression import (
    decompress_G1,
    get_flags,
    is_point_at_infinity,
)
from py_ecc.bls.typing import G1Compressed as G1Compressed_py
from py_ecc.fields import optimized_bls12_381_FQ as BLSF
from py_ecc.optimized_bls12_381.optimized_curve import b, is_inf, is_on_curve
from py_ecc.typing import Optimized_Point3D

from tests.utils.args_gen import U384, BLSPubkey, G1Compressed


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
@example(z1=U384(POW_2_383 + POW_2_382), z2=None)
def test_is_point_at_infinity(cairo_run, z1: U384, z2: Optional[U384]):
    assert cairo_run("is_point_at_infinity", z1, z2) == is_point_at_infinity(
        int(z1), int(z2) if z2 else None
    )


@given(commitment=...)
def test_kzg_commitment_to_versioned_hash(cairo_run, commitment: KZGCommitment):
    assert cairo_run(
        "kzg_commitment_to_versioned_hash", commitment
    ) == kzg_commitment_to_versioned_hash(commitment)


@given(point=...)
@example(
    point=G1Compressed(POW_2_383 + POW_2_382)
)  # c_flag=1, b_flag=1, a_flag=0, infinity point
def test_decompress_G1(cairo_run, point: G1Compressed):
    res, error = cairo_run("decompress_G1", point)
    assert not error
    assert res == decompress_G1(G1Compressed_py(point))


@given(point=st.builds(G1Compressed, st.integers(min_value=0, max_value=POW_2_384 - 1)))
@example(point=G1Compressed(0))
@example(
    point=G1Compressed(POW_2_383)
)  # c_flag=1, b_flag=0, a_flag=0, point at infinity
@example(
    point=G1Compressed(POW_2_383 + POW_2_382 + 1)
)  # c_flag=1, b_flag=1, a_flag=0, non-infinity point
@example(
    point=G1Compressed(POW_2_383 + POW_2_382 + POW_2_381)
)  # c_flag=1, b_flag=1, a_flag=1, infinity point
def test_decompress_G1_error_cases(cairo_run, point: G1Compressed):
    try:
        decompress_G1(G1Compressed_py(point))
    except ValueError:
        _, error = cairo_run("decompress_G1", point)
        assert error


@given(pubkey=...)
def test_pubkey_to_G1(cairo_run, pubkey: BLSPubkey):
    res, error = cairo_run("pubkey_to_g1", pubkey)
    if error:
        with pytest.raises(ValueError):
            pubkey_to_G1(BLSPubkey_py(pubkey))
        return
    assert res == pubkey_to_G1(BLSPubkey_py(pubkey))


@given(pt=...)
def test_is_inf(cairo_run, pt: Optimized_Point3D[BLSF]):
    assert cairo_run("is_inf", pt) == is_inf(pt)


@given(pt=...)
def test_subgroup_check(cairo_run, pt: Optimized_Point3D[BLSF]):
    assert cairo_run("subgroup_check", pt) == subgroup_check(pt)


@given(pubkey=...)
def test_key_validate(cairo_run, pubkey: BLSPubkey):
    assert cairo_run("key_validate", pubkey) == G2ProofOfPossession.KeyValidate(
        BLSPubkey_py(pubkey)
    )


@given(pt=...)
def test_is_on_curve(cairo_run, pt: Optimized_Point3D[BLSF]):
    assert cairo_run("is_on_curve", pt) == is_on_curve(pt, b)


@given(b=...)
@example(Bytes48(b"\xc0" + b"\x00" * 47))
def test_validate_kzg_g1(cairo_run, b: Bytes48):
    try:
        validate_kzg_g1(b)
        is_valid = True
    except AssertionError:
        is_valid = False

    assert cairo_run("validate_kzg_g1", b) == is_valid


@given(b=...)
@example(Bytes48(b"\xc0" + b"\x00" * 47))
def test_bytes_to_kzg_commitment(cairo_run, b: Bytes48):
    (cairo_result, error) = cairo_run("bytes_to_kzg_commitment", b)

    try:
        expected = bytes_to_kzg_commitment(b)
        assert not error
        assert cairo_result == expected
    except AssertionError:
        assert error


@given(b=...)
@example(Bytes48(b"\xc0" + b"\x00" * 47))
def test_bytes_to_kzg_proof(cairo_run, b: Bytes48):
    (cairo_result, error) = cairo_run("bytes_to_kzg_proof", b)

    try:
        expected = bytes_to_kzg_proof(b)
        assert not error
        assert cairo_result == expected
    except AssertionError:
        assert error

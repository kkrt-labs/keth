from typing import Optional, Tuple

import pytest
from eth_typing import BLSPubkey as BLSPubkey_py
from eth_typing.bls import BLSSignature
from ethereum.crypto.kzg import (
    BLS_MODULUS,
    FQ,
    FQ2,
    G1_POINT_AT_INFINITY,
    KZG_SETUP_G2_MONOMIAL_1,
    BLSFieldElement,
    KZGCommitment,
    KZGProof,
    bytes_to_bls_field,
    bytes_to_kzg_commitment,
    bytes_to_kzg_proof,
    kzg_commitment_to_versioned_hash,
    pairing_check,
    validate_kzg_g1,
    verify_kzg_proof,
    verify_kzg_proof_impl,
)
from ethereum.utils.hexadecimal import hex_to_bytes
from ethereum_types.bytes import Bytes, Bytes32, Bytes48
from hypothesis import example, given, settings
from hypothesis import strategies as st
from py_ecc.bls.ciphersuites import G2ProofOfPossession
from py_ecc.bls.constants import POW_2_381, POW_2_382, POW_2_383, POW_2_384
from py_ecc.bls.g2_primitives import pubkey_to_G1, signature_to_G2, subgroup_check
from py_ecc.bls.hash import os2ip
from py_ecc.bls.point_compression import (
    decompress_G1,
    get_flags,
    is_point_at_infinity,
)
from py_ecc.bls.typing import G1Compressed as G1Compressed_py
from py_ecc.fields import optimized_bls12_381_FQ as BLSF
from py_ecc.fields import optimized_bls12_381_FQ2 as BLSF2
from py_ecc.optimized_bls12_381.optimized_curve import (
    G1,
    G2,
    add,
    b,
    is_inf,
    is_on_curve,
    multiply,
)
from py_ecc.optimized_bls12_381.optimized_pairing import normalize1
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


def test_BLSP_G(cairo_run):
    assert cairo_run("BLSP_G") == G1


def test_BLSP2_G(cairo_run):
    assert cairo_run("BLSP2_G") == G2


def test_SIGNATURE_G2(cairo_run):
    assert cairo_run("SIGNATURE_G2") == signature_to_G2(
        BLSSignature(hex_to_bytes(KZG_SETUP_G2_MONOMIAL_1))
    )


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
    assert cairo_run("decompress_g1", point) == decompress_G1(G1Compressed_py(point))


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
        with pytest.raises(ValueError):
            cairo_run("decompress_g1", point)


@given(pubkey=...)
def test_pubkey_to_G1(cairo_run, pubkey: BLSPubkey):
    try:
        pubkey_to_G1(BLSPubkey_py(pubkey))
    except ValueError:
        with pytest.raises(ValueError):
            cairo_run("pubkey_to_g1", pubkey)
        return
    assert cairo_run("pubkey_to_g1", pubkey) == pubkey_to_G1(BLSPubkey_py(pubkey))


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
    except AssertionError:
        with pytest.raises(AssertionError):
            cairo_run("validate_kzg_g1", b)
        return
    cairo_run("validate_kzg_g1", b)


@given(b=...)
@example(Bytes48(b"\xc0" + b"\x00" * 47))
def test_bytes_to_kzg_commitment(cairo_run, b: Bytes48):
    try:
        expected = bytes_to_kzg_commitment(b)
    except AssertionError:
        with pytest.raises(AssertionError):
            cairo_run("bytes_to_kzg_commitment", b)
        return
    assert cairo_run("bytes_to_kzg_commitment", b) == expected


@given(b=...)
@example(Bytes48(b"\xc0" + b"\x00" * 47))
def test_bytes_to_kzg_proof(cairo_run, b: Bytes48):
    try:
        expected = bytes_to_kzg_proof(b)
    except AssertionError:
        with pytest.raises(AssertionError):
            cairo_run("bytes_to_kzg_proof", b)
        return
    assert cairo_run("bytes_to_kzg_proof", b) == expected


@given(b=...)
# Example from https://github.com/crate-crypto/go-kzg-4844/blob/master/tests/verify_kzg_proof/kzg-mainnet/verify_kzg_proof_case_correct_proof_392169c16a2e5ef6/data.yaml
# Value were taken from the python implementation by debugging verify_kzg_proof_impl(commitment, z, y, proof) and normalized by using normalize1
@example(
    b=(
        (
            (
                BLSF(
                    3033089233236390153580784002387749973398519931436392556804430824745663885980591341916949538742661765507761577318725
                ),
                BLSF(
                    1684661300497586024314492375612828779971749284691517756593117745514751654531311468370079927887112854533694448853805
                ),
                BLSF(1),
            ),
            (
                BLSF2(
                    (
                        352701069587466618187139116011060144890029952792775240219908644239793785735715026873347600343865175952761926303160,
                        3059144344244213709971259814753781636986470325476647558659373206291635324768958432433509563104347017837885763365758,
                    )
                ),
                BLSF2(
                    (
                        2017258952934375457849735304558732518256013841723352154472679471057686924117014146018818524865681679396399932211882,
                        3074855889729334937670587859959866275799142626485414915307030157330054773488162299461738339401058098462460928340205,
                    )
                ),
                BLSF2((1, 0)),
            ),
        ),
        (
            (
                BLSF(
                    1620166399879389936119850415613754992405277006589305144301468170849050104387344393734170673840325138234069912381620
                ),
                BLSF(
                    3007297582548210138175653692093564998020771023214829988712167287424386585196076033759114927048825258893439448062492
                ),
                BLSF(1),
            ),
            (
                BLSF2(
                    (
                        2361737525864587121144448160306710977536250284102478515689025532495347985697380558754265254861332443208350014666760,
                        2996122343636714238141262560978394822929902213982512378305369469034694945785613132457694516009925027796537743027516,
                    )
                ),
                BLSF2(
                    (
                        3986422958346626201868818983556384810121772727871500879638238950763353393093723176841556715747752946780355737124790,
                        700792046467811452761458186359099178318372779802175427673275647624598413602723772013116941894289756371290346004973,
                    )
                ),
                BLSF2((1, 0)),
            ),
        ),
    )
)
@settings(max_examples=50)
@pytest.mark.slow
def test_pairing_check(cairo_run, b: Tuple[Tuple[FQ, FQ2], Tuple[FQ, FQ2]]):
    res = pairing_check(b)
    assert cairo_run("pairing_check", b) == res


def test_retrieve_values_for_pairing_check():
    # https://github.com/crate-crypto/go-kzg-4844/blob/master/tests/verify_kzg_proof/kzg-mainnet/verify_kzg_proof_case_correct_proof_392169c16a2e5ef6/data.yaml
    z = BLSFieldElement(
        0x73EDA753299D7D483339D80809A1D80553BDA402FFFE5BFEFFFFFFFF00000000
    )
    y = BLSFieldElement(
        0x304962B3598A0ADF33189FDFD9789FEAB1096FF40006900400000003FFFFFFFC
    )
    commitment = KZGCommitment(
        0xA421E229565952CFFF4EF3517100A97DA1D4FE57956FA50A442F92AF03B1BF37ADACC8AD4ED209B31287EA5BB94D9D06.to_bytes(
            48, "big"
        )
    )
    proof = KZGProof(
        0xAA86C458B3065E7EC244033A2ADE91A7499561F482419A3A372C42A636DAD98262A2CE926D142FD7CFE26CA148EFE8B4.to_bytes(
            48, "big"
        )
    )
    verify_kzg_proof_impl(commitment, z, y, proof)
    # debug and retrieve values of the input of pairing_check function then apply normalize1 to each element


@given(z=...)
@pytest.mark.slow
def test_compute_x_minus_z(cairo_run, z: BLSFieldElement):
    assert cairo_run("compute_x_minus_z", z) == normalize1(
        add(
            signature_to_G2(BLSSignature(hex_to_bytes(KZG_SETUP_G2_MONOMIAL_1))),
            multiply(G2, int((BLS_MODULUS - z) % BLS_MODULUS)),
        )
    )


@given(commitment=..., y=...)
def test_compute_p_minus_y(cairo_run, commitment: KZGCommitment, y: BLSFieldElement):
    try:
        expected = normalize1(
            add(
                pubkey_to_G1(BLSPubkey_py(commitment)),
                multiply(G1, int((BLS_MODULUS - y) % BLS_MODULUS)),
            )
        )
    except ValueError:
        with pytest.raises(ValueError):
            cairo_run("compute_p_minus_y", commitment, y)
        return
    assert cairo_run("compute_p_minus_y", commitment, y) == expected


@given(commitment=..., z=..., y=..., proof=...)
@example(
    commitment=KZGCommitment(
        0xA421E229565952CFFF4EF3517100A97DA1D4FE57956FA50A442F92AF03B1BF37ADACC8AD4ED209B31287EA5BB94D9D06.to_bytes(
            48, "big"
        )
    ),
    z=BLSFieldElement(
        0x73EDA753299D7D483339D80809A1D80553BDA402FFFE5BFEFFFFFFFF00000000
    ),
    y=BLSFieldElement(
        0x304962B3598A0ADF33189FDFD9789FEAB1096FF40006900400000003FFFFFFFC
    ),
    proof=KZGProof(
        0xAA86C458B3065E7EC244033A2ADE91A7499561F482419A3A372C42A636DAD98262A2CE926D142FD7CFE26CA148EFE8B4.to_bytes(
            48, "big"
        )
    ),
)
@example(
    commitment=G1_POINT_AT_INFINITY,
    z=BLS_MODULUS - BLSFieldElement(1),
    y=BLSFieldElement(0),
    proof=KZGProof(G1_POINT_AT_INFINITY),
)
@example(
    commitment=KZGCommitment(
        0xB7F1D3A73197D7942695638C4FA9AC0FC3688C4F9774B905A14E3A3F171BAC586C55E83FF97A1AEFFB3AF00ADB22C6BB.to_bytes(
            48, "big"
        )
    ),
    z=BLSFieldElement(
        0x73EDA753299D7D483339D80809A1D80553BDA402FFFE5BFEFFFFFFFF00000000
    ),
    y=BLSFieldElement(
        0x73EDA753299D7D483339D80809A1D80553BDA402FFFE5BFEFFFFFFFF00000000
    ),
    proof=KZGProof(G1_POINT_AT_INFINITY),
)
@pytest.mark.slow
def test_verify_kzg_proof_impl(
    cairo_run,
    commitment: KZGCommitment,
    z: BLSFieldElement,
    y: BLSFieldElement,
    proof: KZGProof,
):
    try:
        expected = verify_kzg_proof_impl(commitment, z, y, proof)
    except ValueError:
        with pytest.raises(ValueError):
            cairo_run("verify_kzg_proof_impl", commitment, z, y, proof)
        return
    assert cairo_run("verify_kzg_proof_impl", commitment, z, y, proof) == expected


@given(
    commitment_bytes=...,
    z_bytes=...,
    y_bytes=...,
    proof_bytes=...,
)
@example(
    commitment_bytes=0xA421E229565952CFFF4EF3517100A97DA1D4FE57956FA50A442F92AF03B1BF37ADACC8AD4ED209B31287EA5BB94D9D06.to_bytes(
        48, "big"
    ),
    z_bytes=0x73EDA753299D7D483339D80809A1D80553BDA402FFFE5BFEFFFFFFFF00000000.to_bytes(
        32, "big"
    ),
    y_bytes=0x304962B3598A0ADF33189FDFD9789FEAB1096FF40006900400000003FFFFFFFC.to_bytes(
        32, "big"
    ),
    proof_bytes=0xAA86C458B3065E7EC244033A2ADE91A7499561F482419A3A372C42A636DAD98262A2CE926D142FD7CFE26CA148EFE8B4.to_bytes(
        48, "big"
    ),
)
@example(
    commitment_bytes=G1_POINT_AT_INFINITY,
    z_bytes=int(BLS_MODULUS - BLSFieldElement(1)).to_bytes(32, "big"),
    y_bytes=(0).to_bytes(32, "big"),
    proof_bytes=G1_POINT_AT_INFINITY,
)
@example(
    commitment_bytes=0xB7F1D3A73197D7942695638C4FA9AC0FC3688C4F9774B905A14E3A3F171BAC586C55E83FF97A1AEFFB3AF00ADB22C6BB.to_bytes(
        48, "big"
    ),
    z_bytes=0x73EDA753299D7D483339D80809A1D80553BDA402FFFE5BFEFFFFFFFF00000000.to_bytes(
        32, "big"
    ),
    y_bytes=0x73EDA753299D7D483339D80809A1D80553BDA402FFFE5BFEFFFFFFFF00000000.to_bytes(
        32, "big"
    ),
    proof_bytes=G1_POINT_AT_INFINITY,
)
# Test cases for invalid inputs
@example(
    commitment_bytes=G1_POINT_AT_INFINITY,
    z_bytes=int(BLS_MODULUS + BLSFieldElement(1)).to_bytes(32, "big"),
    y_bytes=(0).to_bytes(32, "big"),
    proof_bytes=G1_POINT_AT_INFINITY,
)
@example(
    commitment_bytes=G1_POINT_AT_INFINITY,
    z_bytes=int(BLS_MODULUS - BLSFieldElement(1)).to_bytes(32, "big"),
    y_bytes=int(BLS_MODULUS + BLSFieldElement(1)).to_bytes(32, "big"),
    proof_bytes=G1_POINT_AT_INFINITY,
)
@example(
    commitment_bytes=int(BLS_MODULUS + BLSFieldElement(1)).to_bytes(32, "big"),
    z_bytes=int(BLS_MODULUS - BLSFieldElement(1)).to_bytes(32, "big"),
    y_bytes=(0).to_bytes(32, "big"),
    proof_bytes=G1_POINT_AT_INFINITY,
)
@example(
    commitment_bytes=G1_POINT_AT_INFINITY,
    z_bytes=int(BLS_MODULUS - BLSFieldElement(1)).to_bytes(32, "big"),
    y_bytes=(0).to_bytes(32, "big"),
    proof_bytes=int(BLS_MODULUS + BLSFieldElement(1)).to_bytes(32, "big"),
)
def test_verify_kzg_proof(
    cairo_run,
    commitment_bytes: Bytes48,
    z_bytes: Bytes32,
    y_bytes: Bytes32,
    proof_bytes: Bytes48,
):
    try:
        expected = verify_kzg_proof(commitment_bytes, z_bytes, y_bytes, proof_bytes)
    except (AssertionError, ValueError):
        with pytest.raises((AssertionError, ValueError)):
            cairo_run(
                "verify_kzg_proof", commitment_bytes, z_bytes, y_bytes, proof_bytes
            )
        return

    result = cairo_run(
        "verify_kzg_proof", commitment_bytes, z_bytes, y_bytes, proof_bytes
    )
    assert result == expected

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    UInt384,
    ModBuiltin,
    PoseidonBuiltin,
)
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.common.bitwise import bitwise_and
from starkware.cairo.common.math import unsigned_div_rem
from starkware.cairo.common.math_cmp import is_not_zero
from starkware.cairo.common.memcpy import memcpy
from ethereum_types.bytes import (
    Bytes,
    Bytes4,
    Bytes32,
    Bytes48,
    BytesStruct,
    ListBytes4,
    ListBytes4Struct,
)
from ethereum_types.numeric import U256, U256Struct, U384, bool
from ethereum.utils.bytes import ListBytes4_be_to_bytes, Bytes_to_be_ListBytes4
from ethereum.utils.numeric import (
    U256_from_be_bytes32,
    U256_le,
    U384_from_be_bytes,
    U384_to_le_bytes,
    U384_ZERO,
    U384_ONE,
    U384__eq__,
    Bytes32_from_be_bytes,
    U384Struct,
)
from ethereum.crypto.bls12_381 import (
    blsf_mul,
    BLSF_ONE,
    BLSF_ZERO,
    BLSF,
    BLSF12__eq__,
    blsf12_mul,
    BLSF12_ONE,
    BLSF12,
    BLSF12Struct,
    blsf2_sub,
    BLSF2_ZERO,
    BLSF2,
    BLSF2Struct,
    BLSFStruct,
    BLSP__eq__,
    blsp_add,
    BLSP_G,
    blsp_init,
    blsp_mul_by,
    blsp_point_at_infinity,
    BLSP,
    BLSP2__eq__,
    blsp2_add,
    BLSP2_G,
    blsp2_mul_by,
    blsp2_point_at_infinity,
    BLSP2,
    BLSP2Struct,
    BLSPStruct,
    G1Compressed,
    G1Uncompressed,
    TupleBLSPBLSP2,
    TupleBLSPBLSP2Struct,
    TupleTupleBLSPBLSP2,
    TupleTupleBLSPBLSP2Struct,
)

from bls12_381.multi_pairing_1 import multi_pairing_1P
from cairo_core.hash.sha256 import sha256_be_output
from cairo_core.numeric import OptionalU384
from cairo_ec.circuits.ec_ops_compiled import assert_on_curve
from cairo_ec.circuits.mod_ops_compiled import add, sub, mul
from cairo_ec.curve.bls12_381 import bls12_381
from cairo_ec.curve.g1_point import G1Point
from cairo_ec.uint384 import uint256_to_uint384
from definitions import G1G2Pair, G1Point as G1PointGaraga, G2Point as G2PointGaraga
from ethereum.cancun.fork_types import VersionedHash
from ethereum.exceptions import Exception, ValueError, AssertionError
from legacy.utils.array import reverse

using BLSScalar = U256;
using KZGCommitment = Bytes48;
using KZGProof = Bytes48;
using BLSPubkey = Bytes48;
const VERSIONED_HASH_VERSION_KZG = 0x01;

const GET_FLAGS_MASK = 2 ** 95 + 2 ** 94 + 2 ** 93;
const POW_2_381_D3 = 0x200000000000000000000000;
const G1_POINT_AT_INFINITY_FIRST_BYTE = 0xc0;

func kzg_commitment_to_versioned_hash{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    kzg_commitment: KZGCommitment
) -> VersionedHash {
    alloc_locals;

    // Convert KZG commitment to bytes array
    let bytes_input = U384_to_le_bytes(U384(kzg_commitment.value), 48);

    // Convert the bytes array to a list of bytes4 to hash
    let list_bytes4_be_reverse = Bytes_to_be_ListBytes4(bytes_input);
    let hash = sha256_be_output(list_bytes4_be_reverse.value.data, 48);
    tempvar hash_bytes4 = ListBytes4(new ListBytes4Struct(cast(hash, Bytes4*), 8));
    let hash_bytes = ListBytes4_be_to_bytes(hash_bytes4);

    // Format the output
    let (local result_bytes: felt*) = alloc();
    assert result_bytes[0] = VERSIONED_HASH_VERSION_KZG;
    memcpy(result_bytes + 1, hash_bytes.value.data + 1, 31);
    tempvar bytes_result = Bytes(new BytesStruct(data=result_bytes, len=32));
    let versioned_hash = Bytes32_from_be_bytes(bytes_result);
    tempvar res = VersionedHash(versioned_hash.value);
    return res;
}

func bytes_to_bls_field{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(b: Bytes32) -> (
    BLSScalar, Exception*
) {
    let field_element = U256_from_be_bytes32(b);
    tempvar bls_modulus_minus_one = U256(
        new U256Struct(low=bls12_381.N_LOW_128 - 1, high=bls12_381.N_HIGH_128)
    );
    let is_valid = U256_le(field_element, bls_modulus_minus_one);
    tempvar result = BLSScalar(field_element.value);
    if (is_valid.value != 0) {
        let ok = cast(0, Exception*);
        return (result, ok);
    }
    tempvar err = new Exception(AssertionError);
    return (result, err);
}

// Diverge from specs: limited to 48 bytes
func os2ip{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(b: Bytes) -> U384 {
    let result = U384_from_be_bytes(b);
    return result;
}

// Extract all three most significant bits with one bitwise operation
// Since each limb of z is 96-bit long, the MSB is at position 95 in d3
func get_flags{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(z: U384) -> (bool, bool, bool) {
    let (flags_mask) = bitwise_and(z.value.d3, GET_FLAGS_MASK);
    let (c, remainder1) = unsigned_div_rem(flags_mask, 2 ** 95);
    let (b, remainder2) = unsigned_div_rem(remainder1, 2 ** 94);
    let (a, _) = unsigned_div_rem(remainder2, 2 ** 93);

    let c_flag = is_not_zero(c);
    let b_flag = is_not_zero(b);
    let a_flag = is_not_zero(a);
    return (bool(c_flag), bool(b_flag), bool(a_flag));
}

// Utils for G1 point decompression
func is_point_at_infinity{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(z1: U384, z2: OptionalU384) -> bool {
    alloc_locals;

    let (u384_zero_ptr) = get_label_location(U384_ZERO);
    let u384_zero = U384(cast(u384_zero_ptr, UInt384*));
    let (u384_one_ptr) = get_label_location(U384_ONE);
    let u384_one = U384(cast(u384_one_ptr, UInt384*));
    tempvar POW_2_381 = U384(new U384Struct(0, 0, 0, POW_2_381_D3));
    let z1_mod_2_381 = mul(z1, u384_one, POW_2_381);
    let is_z1_zero = U384__eq__(z1_mod_2_381, u384_zero);
    if (z2.value != 0) {
        let is_z2_zero = U384__eq__(U384(z2.value), u384_zero);
        let result = bool(is_z1_zero.value * is_z2_zero.value);
        return result;
    }
    let result = bool(is_z1_zero.value);
    return result;
}

// Recover the uncompressed g1 point from its compressed form
func decompress_g1{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(z: G1Compressed) -> (G1Uncompressed, Exception*) {
    alloc_locals;

    // Extract flags
    let (c_flag, b_flag, a_flag) = get_flags(z);

    // Validate c_flag is 1
    if (c_flag.value != 1) {
        let one = BLSF_ONE();
        let zero = BLSF_ZERO();
        tempvar dummy = BLSP(new BLSPStruct(zero, one));
        tempvar err = new Exception(ValueError);
        return (dummy, err);
    }

    // Check if the point is at infinity
    tempvar zero_u384 = OptionalU384(new U384Struct(0, 0, 0, 0));
    let is_inf_pt = is_point_at_infinity(z, zero_u384);

    // Validate b_flag
    if (b_flag.value != is_inf_pt.value) {
        let one = BLSF_ONE();
        let zero = BLSF_ZERO();
        tempvar dummy = BLSP(new BLSPStruct(zero, one));
        tempvar err = new Exception(ValueError);
        return (dummy, err);
    }

    // If point is at infinity
    if (is_inf_pt.value != 0) {
        // Validate a_flag is 0
        if (a_flag.value != 0) {
            let one = BLSF_ONE();
            let zero = BLSF_ZERO();
            tempvar dummy = BLSP(new BLSPStruct(zero, one));
            tempvar err = new Exception(ValueError);
            return (dummy, err);
        }
        // Return point at infinity
        let result = blsp_point_at_infinity();
        let ok = cast(0, Exception*);
        return (result, ok);
    }

    // z % POW_2_381
    let (u384_one_ptr) = get_label_location(U384_ONE);
    let u384_one = U384(cast(u384_one_ptr, UInt384*));
    tempvar POW_2_381 = U384(new U384Struct(0, 0, 0, POW_2_381_D3));
    let x = mul(z, u384_one, POW_2_381);

    // Create x as a field element
    tempvar x_blsf = BLSF(new BLSFStruct(x));

    // compute y = (x^3 + b)^((p+1)/4) mod p
    // replaced with a hint
    local y_blsf: BLSF;
    %{ decompress_G1_hint %}

    // Check if the point is on the curve
    tempvar point = BLSP(new BLSPStruct(x_blsf, y_blsf));
    let on_curve = is_on_curve(point);
    if (on_curve.value != 0) {
        let ok = cast(0, Exception*);
        return (point, ok);
    }
    let one = BLSF_ONE();
    let zero = BLSF_ZERO();
    tempvar dummy = BLSP(new BLSPStruct(zero, one));
    tempvar err = new Exception(ValueError);
    return (dummy, err);
}

func pubkey_to_g1{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(pubkey: BLSPubkey) -> (G1Uncompressed, Exception*) {
    alloc_locals;

    let bytes_pubkey = U384_to_le_bytes(U384(pubkey.value), 48);
    let z = os2ip(bytes_pubkey);

    tempvar compressed_point = G1Compressed(z.value);
    let (uncompressed_point, error) = decompress_g1(compressed_point);
    return (uncompressed_point, error);
}

func is_inf{range_check96_ptr: felt*}(pt: BLSP) -> bool {
    alloc_locals;
    let infinity = blsp_point_at_infinity();
    let p_inf = BLSP__eq__(pt, infinity);
    let res = bool(p_inf);
    return res;
}

func subgroup_check{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(p: BLSP) -> bool {
    alloc_locals;
    tempvar curve_order = U384(
        new U384Struct(bls12_381.N0, bls12_381.N1, bls12_381.N2, bls12_381.N3)
    );
    let p_mul = blsp_mul_by(p, curve_order);
    let result = is_inf(p_mul);
    return result;
}

func is_on_curve{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(p: BLSP) -> bool {
    alloc_locals;

    let is_infinity = is_inf(p);
    if (is_infinity.value != 0) {
        let result = bool(1);
        return result;
    }

    let y_2 = blsf_mul(p.value.y, p.value.y);
    let x_2 = blsf_mul(p.value.x, p.value.x);
    let x_3 = blsf_mul(p.value.x, x_2);
    tempvar b = U384(new U384Struct(bls12_381.B0, bls12_381.B1, bls12_381.B2, bls12_381.B3));
    tempvar modulus = U384(new U384Struct(bls12_381.P0, bls12_381.P1, bls12_381.P2, bls12_381.P3));
    let rhs = add(x_3.value.c0, b, modulus);
    let result = U384__eq__(y_2.value.c0, rhs);

    return result;
}

func key_validate{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(pk: BLSPubkey) -> bool {
    alloc_locals;

    let (point, error) = pubkey_to_g1(pk);
    if (cast(error, felt) != 0) {
        let result = bool(0);
        return result;
    }

    let is_infinity = is_inf(point);
    if (is_infinity.value != 0) {
        let result = bool(0);
        return result;
    }

    let in_subgroup = subgroup_check(point);
    if (in_subgroup.value != 0) {
        let result = bool(1);
        return result;
    }

    let result = bool(0);
    return result;
}

func validate_kzg_g1{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(b: Bytes48) -> Exception* {
    alloc_locals;

    tempvar infinity_point = U384(new UInt384(G1_POINT_AT_INFINITY_FIRST_BYTE, 0, 0, 0));
    let is_infinity = U384__eq__(U384(b.value), infinity_point);
    if (is_infinity.value != 0) {
        let ok = cast(0, Exception*);
        return ok;
    }

    let is_valid = key_validate(b);
    if (is_valid.value != 0) {
        let ok = cast(0, Exception*);
        return ok;
    }
    tempvar err = new Exception(AssertionError);
    return err;
}

func bytes_to_kzg_commitment{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(b: Bytes48) -> (KZGCommitment, Exception*) {
    let err = validate_kzg_g1(b);
    if (cast(err, felt) != 0) {
        tempvar err = new Exception(AssertionError);
        return (KZGCommitment(b.value), err);
    }
    let ok = cast(0, Exception*);
    return (KZGCommitment(b.value), ok);
}

func bytes_to_kzg_proof{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(b: Bytes48) -> (KZGProof, Exception*) {
    let err = validate_kzg_g1(b);
    if (cast(err, felt) != 0) {
        tempvar err = new Exception(AssertionError);
        return (KZGProof(b.value), err);
    }
    let ok = cast(0, Exception*);
    return (KZGProof(b.value), ok);
}

// Pairing check for BLS12-381
// For each pairing, if one of the points is at infinity, the result is 1
func pairing_check{
    range_check_ptr,
    range_check96_ptr: felt*,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(pairs: TupleTupleBLSPBLSP2) -> bool {
    alloc_locals;

    // First pair
    let pair1 = pairs.value.pair1;
    let p = pair1.value.blsp;
    let q = pair1.value.blsp2;

    let infinity_p = blsp_point_at_infinity();
    let is_infinity_p = BLSP__eq__(p, infinity_p);
    let infinity_q = blsp2_point_at_infinity();
    let is_infinity_q = BLSP2__eq__(q, infinity_q);
    let is_infinity = is_infinity_p + is_infinity_q;

    if (is_infinity != 0) {
        let res1_temp = BLSF12_ONE();
        tempvar range_check_ptr = range_check_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
    } else {
        let p_garaga = G1PointGaraga([p.value.x.value.c0.value], [p.value.y.value.c0.value]);
        let q_garaga = G2PointGaraga(
            [q.value.x.value.c0.value],
            [q.value.x.value.c1.value],
            [q.value.y.value.c0.value],
            [q.value.y.value.c1.value],
        );
        tempvar pair = new G1G2Pair(p_garaga, q_garaga);
        let (res_garaga) = multi_pairing_1P(pair);
        tempvar res1_temp = BLSF12(
            new BLSF12Struct(
                U384(new res_garaga.w0),
                U384(new res_garaga.w1),
                U384(new res_garaga.w2),
                U384(new res_garaga.w3),
                U384(new res_garaga.w4),
                U384(new res_garaga.w5),
                U384(new res_garaga.w6),
                U384(new res_garaga.w7),
                U384(new res_garaga.w8),
                U384(new res_garaga.w9),
                U384(new res_garaga.w10),
                U384(new res_garaga.w11),
            ),
        );
        tempvar range_check_ptr = range_check_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
    }
    let res1_temp = BLSF12(cast([ap - 6], BLSF12Struct*));
    let range_check_ptr = [ap - 5];
    let poseidon_ptr = cast([ap - 4], PoseidonBuiltin*);
    let range_check96_ptr = cast([ap - 3], felt*);
    let add_mod_ptr = cast([ap - 2], ModBuiltin*);
    let mul_mod_ptr = cast([ap - 1], ModBuiltin*);

    tempvar res1_temp = res1_temp;

    // Second pair
    let pair2 = pairs.value.pair2;
    let p = pair2.value.blsp;
    let q = pair2.value.blsp2;

    let infinity_p = blsp_point_at_infinity();
    let is_infinity = BLSP__eq__(p, infinity_p);
    let infinity_q = blsp2_point_at_infinity();
    let is_infinity_q = BLSP2__eq__(q, infinity_q);
    let is_infinity = is_infinity + is_infinity_q;

    if (is_infinity != 0) {
        let res2_temp = BLSF12_ONE();
        tempvar res2_temp = res2_temp;

        tempvar res1_temp = res1_temp;
        tempvar res2_temp = res2_temp;
        tempvar range_check_ptr = range_check_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
    } else {
        let p_garaga = G1PointGaraga([p.value.x.value.c0.value], [p.value.y.value.c0.value]);
        let q_garaga = G2PointGaraga(
            [q.value.x.value.c0.value],
            [q.value.x.value.c1.value],
            [q.value.y.value.c0.value],
            [q.value.y.value.c1.value],
        );
        tempvar input = new G1G2Pair(p_garaga, q_garaga);
        let (res_garaga) = multi_pairing_1P(input);
        tempvar res2_temp = BLSF12(
            new BLSF12Struct(
                U384(new res_garaga.w0),
                U384(new res_garaga.w1),
                U384(new res_garaga.w2),
                U384(new res_garaga.w3),
                U384(new res_garaga.w4),
                U384(new res_garaga.w5),
                U384(new res_garaga.w6),
                U384(new res_garaga.w7),
                U384(new res_garaga.w8),
                U384(new res_garaga.w9),
                U384(new res_garaga.w10),
                U384(new res_garaga.w11),
            ),
        );

        tempvar res1_temp = res1_temp;
        tempvar res2_temp = res2_temp;
        tempvar range_check_ptr = range_check_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
    }
    let res1_temp = BLSF12(cast([ap - 7], BLSF12Struct*));
    let res2_temp = BLSF12(cast([ap - 6], BLSF12Struct*));
    let range_check_ptr = [ap - 5];
    let poseidon_ptr = cast([ap - 4], PoseidonBuiltin*);
    let range_check96_ptr = cast([ap - 3], felt*);
    let add_mod_ptr = cast([ap - 2], ModBuiltin*);
    let mul_mod_ptr = cast([ap - 1], ModBuiltin*);

    let one = BLSF12_ONE();
    let check = blsf12_mul(res1_temp, res2_temp);
    let pairing_check_res = BLSF12__eq__(check, one);

    if (pairing_check_res != 0) {
        tempvar res = bool(1);
        return res;
    }
    tempvar res = bool(0);
    return res;
}

// https://github.com/ethereum/execution-specs/blob/2926c00c1d130e5d0641d278012d42267f3feaf3/src/ethereum/crypto/kzg.py#L173C1
func SIGNATURE_G2() -> BLSP2 {
    tempvar signature_g2 = BLSP2(
        new BLSP2Struct(
            BLSF2(
                new BLSF2Struct(
                    U384(
                        new U384Struct(
                            0x621000edc98edada20c1def2,
                            0xa36851477ba4c60b087041de,
                            0xb38608e23926c911cceceac9,
                            0x185cbfee53492714734429b7,
                        ),
                    ),
                    U384(
                        new U384Struct(
                            0xcb452d2afaaab24f3499f72,
                            0x1009a2ce615ac53d2914e587,
                            0x230af38926187075cbfbefa8,
                            0x15bfd7dd8cdeb128843bc287,
                        ),
                    ),
                ),
            ),
            BLSF2(
                new BLSF2Struct(
                    U384(
                        new U384Struct(
                            0x5941f383ee689bfbbb832a99,
                            0xe82451a496a9c9794ce26d10,
                            0x99d1fca2131569490e28de18,
                            0x14353bdb96b626dd7d5ee85,
                        ),
                    ),
                    U384(
                        new U384Struct(
                            0x3d7ac9cd23048ef30d0a154f,
                            0xda5ed1ba9bfa07899495346f,
                            0xe0181b4bef79de09fc63671f,
                            0x1666c54b0a32529503432fca,
                        ),
                    ),
                ),
            ),
        ),
    );

    return signature_g2;
}

// Compute Q * (X - z)
// https://github.com/ethereum/execution-specs/blob/2926c00c1d130e5d0641d278012d42267f3feaf3/src/ethereum/crypto/kzg.py#L172
func compute_x_minus_z{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(z: BLSScalar) -> BLSP2 {
    alloc_locals;

    tempvar n = U384(new UInt384(bls12_381.N0, bls12_381.N1, bls12_381.N2, bls12_381.N3));
    let z_uint384 = uint256_to_uint384([z.value]);
    tempvar z_u384 = U384(new z_uint384);
    let neg_z = sub(n, z_u384, n);
    let g2 = BLSP2_G();
    let neg_z_g2 = blsp2_mul_by(g2, neg_z);

    let signature_g2 = SIGNATURE_G2();
    let res = blsp2_add(signature_g2, neg_z_g2);
    return res;
}

// Compute P - y
// https://github.com/ethereum/execution-specs/blob/2926c00c1d130e5d0641d278012d42267f3feaf3/src/ethereum/crypto/kzg.py#L176
func compute_p_minus_y{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(commitment: KZGCommitment, y: BLSScalar) -> (BLSP, Exception*) {
    alloc_locals;

    tempvar n = U384(new UInt384(bls12_381.N0, bls12_381.N1, bls12_381.N2, bls12_381.N3));
    let y_uint384 = uint256_to_uint384([y.value]);
    tempvar y_u384 = U384(new y_uint384);
    let neg_y = sub(n, y_u384, n);
    let g1 = BLSP_G();
    let neg_y_g1 = blsp_mul_by(g1, neg_y);

    let (pubkey_from_commitment, error) = pubkey_to_g1(commitment);
    if (cast(error, felt) != 0) {
        tempvar err = new Exception(ValueError);
        return (pubkey_from_commitment, err);
    }

    let p_minus_y = blsp_add(pubkey_from_commitment, neg_y_g1);
    let ok = cast(0, Exception*);
    return (p_minus_y, ok);
}

// Verify KZG proof that `p(z) == y` where `p(z)`
// is the polynomial represented by `polynomial_kzg`.
// @dev Verify: P - y = Q * (X - z)
func verify_kzg_proof_impl{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(commitment: KZGCommitment, z: BLSScalar, y: BLSScalar, proof: KZGProof) -> (bool, Exception*) {
    alloc_locals;

    // Compute Q * (X - z)
    let x_minus_z = compute_x_minus_z(z);
    // Compute P - y
    let (p_minus_y, error) = compute_p_minus_y(commitment, y);
    if (cast(error, felt) != 0) {
        tempvar err = new Exception(ValueError);
        tempvar res = bool(0);
        return (res, err);
    }
    // Compute -g2
    let g2 = BLSP2_G();
    let blsf2_zero = BLSF2_ZERO();
    let neg_y_g2 = blsf2_sub(blsf2_zero, g2.value.y);
    tempvar neg_g2 = BLSP2(new BLSP2Struct(g2.value.x, neg_y_g2));

    // Compute pubkey_from_proof
    let (pubkey_from_proof, error) = pubkey_to_g1(proof);
    if (cast(error, felt) != 0) {
        tempvar err = new Exception(ValueError);
        tempvar res = bool(0);
        return (res, err);
    }

    // Pairing check
    tempvar pair1 = TupleBLSPBLSP2(new TupleBLSPBLSP2Struct(p_minus_y, neg_g2));
    tempvar pair2 = TupleBLSPBLSP2(new TupleBLSPBLSP2Struct(pubkey_from_proof, x_minus_z));
    tempvar pairs = TupleTupleBLSPBLSP2(new TupleTupleBLSPBLSP2Struct(pair1, pair2));
    let res = pairing_check(pairs);

    let ok = cast(0, Exception*);
    return (res, ok);
}

// Convert input bytes to their respective types
// and call the verify_kzg_proof_impl function
func verify_kzg_proof{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(commitment_bytes: Bytes48, z_bytes: Bytes32, y_bytes: Bytes32, proof_bytes: Bytes48) -> (
    bool, Exception*
) {
    alloc_locals;

    let (commitment, err_commitment) = bytes_to_kzg_commitment(commitment_bytes);
    if (cast(err_commitment, felt) != 0) {
        return (bool(0), err_commitment);
    }

    let (z, err_z) = bytes_to_bls_field(z_bytes);
    if (cast(err_z, felt) != 0) {
        return (bool(0), err_z);
    }

    let (y, err_y) = bytes_to_bls_field(y_bytes);
    if (cast(err_y, felt) != 0) {
        return (bool(0), err_y);
    }

    let (proof, err_proof) = bytes_to_kzg_proof(proof_bytes);
    if (cast(err_proof, felt) != 0) {
        return (bool(0), err_proof);
    }

    let (result, err) = verify_kzg_proof_impl(commitment, z, y, proof);
    return (result, err);
}

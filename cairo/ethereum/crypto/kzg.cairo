from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, UInt384, ModBuiltin
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
    U384_to_be_bytes,
    U384_ZERO,
    U384_ONE,
    U384__eq__,
    Bytes32_from_be_bytes,
    U384Struct,
)
from ethereum.crypto.bls12_381 import (
    BLSF,
    BLSFStruct,
    blsf_mul,
    blsf_add,
    BLSP,
    BLSP__eq__,
    BLSPStruct,
    blsp_point_at_infinity,
    blsp_init,
    blsp_mul_by,
    G1Compressed,
    G1Uncompressed,
    BLSF_ZERO,
    BLSF_ONE,
)
from ethereum.cancun.fork_types import VersionedHash
from ethereum.exceptions import Exception, ValueError, AssertionError
from cairo_ec.circuits.ec_ops_compiled import assert_on_curve
from cairo_ec.circuits.mod_ops_compiled import add, sub, mul
from cairo_ec.curve.bls12_381 import bls12_381
from cairo_ec.curve.g1_point import G1Point
from cairo_core.hash.sha256 import sha256_be_output
from cairo_core.numeric import OptionalU384
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

    // Convert KZG commitment to a big-endian bytes array
    let bytes_input = U384_to_be_bytes(U384(kzg_commitment.value), 48);
    let (local bytes_input_reversed: felt*) = alloc();
    reverse(bytes_input_reversed, 48, bytes_input.value.data);
    tempvar bytes_input_reversed_bytes = Bytes(new BytesStruct(data=bytes_input_reversed, len=48));

    // Convert the bytes array to a list of bytes4 to hash
    let list_bytes4_be_reverse = Bytes_to_be_ListBytes4(bytes_input_reversed_bytes);
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
    tempvar bls_modulus = U256(new U256Struct(low=bls12_381.N_LOW_128, high=bls12_381.N_HIGH_128));
    let is_valid = U256_le(field_element, bls_modulus);
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

    let bytes_pubkey = U384_to_be_bytes(U384(pubkey.value), 48);
    let (local bytes_input: felt*) = alloc();
    reverse(bytes_input, 48, bytes_pubkey.value.data);
    tempvar bytes_input_bytes = Bytes(new BytesStruct(data=bytes_input, len=48));
    let z = os2ip(bytes_input_bytes);

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

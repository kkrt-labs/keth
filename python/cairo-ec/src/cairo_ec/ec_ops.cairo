from starkware.cairo.common.cairo_builtins import UInt384, ModBuiltin, PoseidonBuiltin
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.poseidon_state import PoseidonBuiltinState
from cairo_core.maths import assert_uint256_le
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memcpy import memcpy

from cairo_ec.circuits.ec_ops_compiled import (
    ec_add as ec_add_unchecked,
    ec_double,
    assert_x_is_on_curve,
    ecip_1p,
)
from cairo_ec.circuits.mod_ops_compiled import add, mul
from cairo_ec.circuit_utils import N_LIMBS, hash_full_transcript
from cairo_ec.curve.alt_bn128 import alt_bn128, sign_to_uint384_mod_alt_bn128
from cairo_ec.curve.g1_point import G1Point, G1PointStruct, G1Point__eq__, G1Point_zero
from cairo_ec.uint384 import (
    felt_to_uint384,
    uint256_to_uint384,
    uint384_eq,
    uint384_eq_mod_p,
    uint384_is_neg_mod_p,
    uint384_to_uint256,
)
from cairo_ec.curve_utils import scalar_to_epns
from cairo_core.numeric import U384, U384Struct
// @notice Attempts to derive a y-coordinate for a given x on an elliptic curve.
// @return y A candidate y-coordinate; if is_on_curve = 1, (x, y) is on the curve; if 0, y is a fallback value.
// @return is_on_curve 1 if (x, y) lies on the curve, 0 if not.
// @dev Given x, computes y such that y^2 = x^3 + ax + b mod p when is_on_curve = 1, confirming (x, y) is on the curve.
//      If is_on_curve = 0, y^2 = g * (x^3 + ax + b) mod p, where g is generator of the group,
//      s.t it satisfies assert_x_is_on_curve. This y is a fallback and may not be used directly;
//      e.g., get_random_point retries with a new seed instead, but is used to ensure the operation is sound.
// @param x The x-coordinate to test (UInt384)
// @param v Unused flag (TODO: clarify purpose)
// @param a Curve coefficient a (UInt384)
// @param b Curve coefficient b (UInt384)
// @param g Scalar tweak applied when is_on_curve = 0
// @param p Modulus of the field (UInt384)
// @return (y: UInt384*, is_on_curve: felt) The derived y and success flag
func try_get_point_from_x{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(x: UInt384*, v: felt, a: UInt384*, b: UInt384*, g: UInt384*, p: UInt384*) -> (
    y: UInt384*, is_on_curve: felt
) {
    alloc_locals;
    let (__fp__, __pc__) = get_fp_and_pc();
    local is_on_curve: UInt384;
    local y_try: UInt384;
    %{ compute_y_from_x_hint %}

    assert_x_is_on_curve(x=x, y=&y_try, a=a, b=b, g=g, is_on_curve=&is_on_curve, p=p);
    assert is_on_curve.d3 = 0;
    assert is_on_curve.d2 = 0;
    assert is_on_curve.d1 = 0;
    // TODO: Add a check for v

    return (y=&y_try, is_on_curve=is_on_curve.d0);
}

// @notice Get a random point from x
func get_random_point{
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(seed: felt, a: U384, b: U384, g: U384, p: U384) -> G1Point {
    alloc_locals;
    let (__fp__, __pc__) = get_fp_and_pc();
    let x_384 = felt_to_uint384(seed);
    tempvar x = new x_384;
    let (y, is_on_curve) = try_get_point_from_x(
        x=x, v=0, a=a.value, b=b.value, g=g.value, p=p.value
    );

    if (is_on_curve != 0) {
        tempvar point = G1Point(new G1PointStruct(U384(x), U384(y)));
        return point;
    }

    assert poseidon_ptr[0].input.s0 = seed;
    assert poseidon_ptr[0].input.s1 = y.d0;  // salt
    assert poseidon_ptr[0].input.s2 = 2;
    let seed = poseidon_ptr[0].output.s0;
    tempvar poseidon_ptr = poseidon_ptr + PoseidonBuiltin.SIZE;

    return get_random_point(seed=seed, a=a, b=b, g=g, p=p);
}

// / @notice Adds two EC points on the ALT_BN128 curve.
// / @dev Handles the point at infinity (0, 0) by returning the other point if either input is infinity.
// /      For points with the same x-coordinate modulo modulus, returns infinity if they are inverses (p.y + q.y = 0 mod P),
// /      or doubles the point if they are equal. Otherwise, performs standard addition for distinct points.
// /      Does not check if inputs lie on the curve; this is the caller's responsibility.
// / @param p The first elliptic curve point as a G1Point struct.
// / @param q The second elliptic curve point as a G1Point struct.
// / @param a The curve coefficient 'a' as a UInt384.
// / @param modulus The prime modulus of the field as a UInt384.
// / @return The resulting point from p + q on the ALT_BN128 curve as a G1Point.
func ec_add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    p: G1Point, q: G1Point, a: U384, modulus: U384
) -> G1Point {
    alloc_locals;
    let inf_point = G1Point_zero();
    let p_is_inf = G1Point__eq__(p, inf_point);
    if (p_is_inf.value != 0) {
        return q;
    }
    let q_is_inf = G1Point__eq__(q, inf_point);
    if (q_is_inf.value != 0) {
        return p;
    }
    let same_x = uint384_eq_mod_p(p.value.x, q.value.x, modulus);
    let (__fp__, __pc__) = get_fp_and_pc();
    if (same_x != 0) {
        let opposite_y = uint384_is_neg_mod_p(p.value.y, q.value.y, modulus);
        if (opposite_y != 0) {
            // p + (-p) = O (point at infinity)
            return inf_point;
        }

        let (res_x, res_y) = ec_double(p.value.x.value, p.value.y.value, a.value, modulus.value);
        tempvar res = G1Point(new G1PointStruct(U384(res_x), U384(res_y)));
        return res;
    }

    let (res_x, res_y) = ec_add_unchecked(
        p.value.x.value, p.value.y.value, q.value.x.value, q.value.y.value, modulus.value
    );
    tempvar res = G1Point(new G1PointStruct(U384(res_x), U384(res_y)));
    return res;
}

// Perform scalar multiplication of an EC point of the alt_bn128 curve.
// Does not early return if input point is point at infinity.
// Fails if input point is not on alt_bn128 (bn254) curve.
func ec_mul{
    range_check_ptr,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(p: G1Point, k: U384, modulus: U384) -> G1Point {
    alloc_locals;
    let (__fp__, _) = get_fp_and_pc();

    tempvar zero_u384 = U384(new U384Struct(0, 0, 0, 0));
    let scalar_is_zero = uint384_eq_mod_p(k, zero_u384, modulus);
    if (scalar_is_zero != 0) {
        let point_at_infinity = G1Point_zero();
        return point_at_infinity;
    }

    tempvar one_u384 = U384(new U384Struct(1, 0, 0, 0));
    tempvar n = U384(new U384Struct(alt_bn128.N0, alt_bn128.N1, alt_bn128.N2, alt_bn128.N3));
    let rem = mul(k.value, one_u384.value, n.value);
    let scalar = uint384_to_uint256([rem]);
    let n_min_one = Uint256(alt_bn128.N_LOW_128 - 1, alt_bn128.N_HIGH_128);
    assert_uint256_le(scalar, n_min_one);

    let (ep_low, en_low, sp_low, sn_low) = scalar_to_epns(scalar.low);
    let ep_low_u384 = felt_to_uint384(ep_low);
    let en_low_u384 = felt_to_uint384(en_low);
    let sp_low_u384 = sign_to_uint384_mod_alt_bn128(sp_low);
    let sn_low_u384 = sign_to_uint384_mod_alt_bn128(sn_low);

    let (ep_high, en_high, sp_high, sn_high) = scalar_to_epns(scalar.high);
    let ep_high_u384 = felt_to_uint384(ep_high);
    let en_high_u384 = felt_to_uint384(en_high);
    let sp_high_u384 = sign_to_uint384_mod_alt_bn128(sp_high);
    let sn_high_u384 = sign_to_uint384_mod_alt_bn128(sn_high);

    %{ ec_mul_msm_hints_and_fill_memory %}

    // Interaction with Poseidon, protocol is roughly a sequence of hashing:
    // - initial constant 'MSM_G1'
    // - curve ID
    // - Number of scalars in MSM
    // - user input P point
    //
    // ==> interaction
    //
    // > get random linear combination coefficients
    //
    // ==> interaction
    // > get seed for random point

    // rlc_coeff is casted to Uint384 after hashing the values of Q (which is used to compute rlc_coeff)
    tempvar rlc_coeff_u384_cast_offset = N_LIMBS;
    tempvar is_on_curve_flags_offset = 2 * N_LIMBS;
    tempvar ecip_circuit_constants_offset = 6 * N_LIMBS;
    tempvar ecip_circuit_q_offset = 32 * N_LIMBS;

    // ! If the offsets are not computed in a tempvar, the range_check96_ptr addition only takes the first member of the addition
    // ! -> A Relocatable + (sum of felts) is not yielding the correct result
    tempvar q_limbs_offset = is_on_curve_flags_offset + rlc_coeff_u384_cast_offset +
        ecip_circuit_constants_offset + ecip_circuit_q_offset;
    let q_limbs: UInt384* = cast(range_check96_ptr + q_limbs_offset, UInt384*);

    let q_low_x = &q_limbs[0];
    let q_low_y = &q_limbs[1];
    let q_high_x = &q_limbs[2];
    let q_high_y = &q_limbs[3];
    let q_high_shifted_x = &q_limbs[4];
    let q_high_shifted_y = &q_limbs[5];
    tempvar q_low = G1Point(new G1PointStruct(U384(q_low_x), U384(q_low_y)));
    tempvar q_high = G1Point(new G1PointStruct(U384(q_high_x), U384(q_high_y)));

    // Compute flag is_on_curve_q_low and is_on_curve_q_high
    let pt_at_inf = G1Point_zero();
    let is_pt_at_inf_q_low = G1Point__eq__(q_low, pt_at_inf);
    let is_pt_at_inf_q_high = G1Point__eq__(q_high, pt_at_inf);
    let is_pt_at_inf_q_low_u384 = felt_to_uint384(is_pt_at_inf_q_low.value);
    let is_pt_at_inf_q_high_u384 = felt_to_uint384(is_pt_at_inf_q_high.value);

    let msm_size = 1;
    assert poseidon_ptr[0].input = PoseidonBuiltinState(s0='MSM_G1', s1=0, s2=1);
    assert poseidon_ptr[1].input = PoseidonBuiltinState(
        s0=alt_bn128.CURVE_ID + poseidon_ptr[0].output.s0,
        s1=msm_size + poseidon_ptr[0].output.s1,
        s2=poseidon_ptr[0].output.s2,
    );
    let poseidon_ptr = poseidon_ptr + 2 * PoseidonBuiltin.SIZE;

    // TODO: check whether we can simplify this
    let (p_limbs: felt*) = alloc();
    memcpy(p_limbs, p.value.x.value, 4);
    memcpy(p_limbs + 4, p.value.y.value, 4);
    hash_full_transcript(p_limbs, 2);

    // Q_low, Q_high, Q_high_shifted (filled by prover) (32 - 37).
    hash_full_transcript(
        range_check96_ptr + rlc_coeff_u384_cast_offset + ecip_circuit_constants_offset +
        ecip_circuit_q_offset,
        3 * 2,
    );
    let _s0 = [cast(poseidon_ptr, felt*) - 3];
    let _s1 = [cast(poseidon_ptr, felt*) - 2];
    let _s2 = [cast(poseidon_ptr, felt*) - 1];

    // scalar k
    assert poseidon_ptr[0].input = PoseidonBuiltinState(
        s0=_s0 + scalar.low, s1=_s1 + scalar.high, s2=_s2
    );
    tempvar rlc_coeff = poseidon_ptr[0].output.s1;
    let poseidon_ptr = poseidon_ptr + PoseidonBuiltin.SIZE;
    let rlc_coeff_u384 = felt_to_uint384(rlc_coeff);

    // Hash sum_dlog_div 2 points : (0-21)
    tempvar a = UInt384(alt_bn128.A0, alt_bn128.A1, alt_bn128.A2, alt_bn128.A3);
    tempvar b = UInt384(alt_bn128.B0, alt_bn128.B1, alt_bn128.B2, alt_bn128.B3);
    tempvar g = UInt384(alt_bn128.G0, alt_bn128.G1, alt_bn128.G2, alt_bn128.G3);
    hash_full_transcript(range_check96_ptr + ecip_circuit_constants_offset, 22);
    tempvar range_check96_ptr_init = range_check96_ptr;
    tempvar range_check96_ptr_after_circuit = range_check96_ptr + 1092;
    let random_point = get_random_point{range_check96_ptr=range_check96_ptr_after_circuit}(
        seed=[cast(poseidon_ptr, felt*) - 3], a=U384(&a), b=U384(&b), g=U384(&g), p=modulus
    );
    let range_check96_ptr = range_check96_ptr_init;

    // Circuits inputs
    let ecip_input: UInt384* = cast(range_check96_ptr + ecip_circuit_constants_offset, UInt384*);
    // Random Linear Combination Sum of Discrete Logarithm Division
    // rlc_sum_dlog_div for 2 points: n_coeffs = 14 + 4 * 2 = 22 (0-21)
    // q_low, q_high, q_high_shifted (32 - 37)
    let random_point_x = random_point.value.x;
    let random_point_y = random_point.value.y;

    ecip_1p(
        &ecip_input[0],
        &ecip_input[1],
        &ecip_input[2],
        &ecip_input[3],
        &ecip_input[4],
        &ecip_input[5],
        &ecip_input[6],
        &ecip_input[7],
        &ecip_input[8],
        &ecip_input[9],
        &ecip_input[10],
        &ecip_input[11],
        &ecip_input[12],
        &ecip_input[13],
        &ecip_input[14],
        &ecip_input[15],
        &ecip_input[16],
        &ecip_input[17],
        &ecip_input[18],
        &ecip_input[19],
        &ecip_input[20],
        &ecip_input[21],
        p.value.x.value,
        p.value.y.value,
        &ep_low_u384,
        &en_low_u384,
        &sp_low_u384,
        &sn_low_u384,
        &ep_high_u384,
        &en_high_u384,
        &sp_high_u384,
        &sn_high_u384,
        q_low_x,
        q_low_y,
        q_high_x,
        q_high_y,
        q_high_shifted_x,
        q_high_shifted_y,
        random_point_x.value,
        random_point_y.value,
        &a,
        &b,
        &rlc_coeff_u384,
        new is_pt_at_inf_q_low_u384,
        new is_pt_at_inf_q_high_u384,
        modulus.value,
    );

    let range_check96_ptr = range_check96_ptr_after_circuit;

    let res = ec_add(
        G1Point(new G1PointStruct(U384(q_low_x), U384(q_low_y))),
        G1Point(new G1PointStruct(U384(q_high_shifted_x), U384(q_high_shifted_y))),
        U384(&a),
        modulus,
    );

    let max_value = Uint256(alt_bn128.P_LOW_128 - 1, alt_bn128.P_HIGH_128);
    let x_uint256 = uint384_to_uint256([res.value.x.value]);
    assert_uint256_le(x_uint256, max_value);
    let y_uint256 = uint384_to_uint256([res.value.y.value]);
    assert_uint256_le(y_uint256, max_value);

    return res;
}

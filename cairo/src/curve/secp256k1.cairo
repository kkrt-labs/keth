from starkware.cairo.common.cairo_builtins import UInt384, ModBuiltin, PoseidonBuiltin
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.common.modulo import run_mod_p_circuit

from src.curve.g1_point import G1Point
from src.utils.uint384 import felt_to_uint384, uint384_is_neg_mod_p, uint384_eq_mod_p

namespace secp256k1 {
    const CURVE_ID = 2;
    const P0 = 0xfffffffffffffffefffffc2f;
    const P1 = 0xffffffffffffffffffffffff;
    const P2 = 0xffffffffffffffff;
    const P3 = 0x0;
    const P_LOW_128 = 0xfffffffffffffffffffffffefffffc2f;
    const P_HIGH_128 = 0xffffffffffffffffffffffffffffffff;
    const N0 = 0xaf48a03bbfd25e8cd0364141;
    const N1 = 0xfffffffffffffffebaaedce6;
    const N2 = 0xffffffffffffffff;
    const N3 = 0x0;
    const N_LOW_128 = 0xbaaedce6af48a03bbfd25e8cd0364141;
    const N_HIGH_128 = 0xfffffffffffffffffffffffffffffffe;
    const A0 = 0x0;
    const A1 = 0x0;
    const A2 = 0x0;
    const A3 = 0x0;
    const B0 = 0x7;
    const B1 = 0x0;
    const B2 = 0x0;
    const B3 = 0x0;
    const G0 = 0x3;
    const G1 = 0x0;
    const G2 = 0x0;
    const G3 = 0x0;
    const MIN_ONE_D0 = 0xfffffffffffffffefffffc2e;
    const MIN_ONE_D1 = 0xffffffffffffffffffffffff;
    const MIN_ONE_D2 = 0xffffffffffffffff;
    const MIN_ONE_D3 = 0x0;
}

// @notice generator_point = (
//     0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798,
//     0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8
// )
// @dev Split in 96 bits chunks
func get_generator_point() -> G1Point* {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let generator_ptr = pc + (generator_label - pc_label);

    return cast(generator_ptr, G1Point*);

    generator_label:
    dw 0x2dce28d959f2815b16f81798;  // x.d0
    dw 0x55a06295ce870b07029bfcdb;  // x.d1
    dw 0x79be667ef9dcbbac;  // x.d2
    dw 0x0;  // x.d3
    dw 0xa68554199c47d08ffb10d4b8;  // y.d0
    dw 0x5da4fbfc0e1108a8fd17b448;  // y.d1
    dw 0x483ada7726a3c465;  // y.d2
    dw 0x0;  // y.d3
}

// @notice Try to get the point from x.
// @return y The y point such that (x, y) is on the curve if success is 1, otherwise (g*h, y) is on the curve
// @return is_on_curve 1 if the point is on the curve, 0 otherwise
// @dev g is the generator point and h is the hash of the message
func try_get_point_from_x{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(x: UInt384, v: felt) -> (y: UInt384, is_on_curve: felt) {
    alloc_locals;
    let add_mod_n = 5;
    let (add_offsets_ptr) = get_label_location(add_offsets_ptr_loc);
    let mul_mod_n = 7;
    let (mul_offsets_ptr) = get_label_location(mul_offsets_ptr_loc);

    local is_on_curve: felt;
    local y_try: UInt384;
    %{
        from starkware.python.math_utils import is_quad_residue
        from sympy import sqrt_mod
        from garaga.definitions import CURVES, CurveID
        from garaga.hints.io import bigint_pack, bigint_fill
        curve_id = CurveID.SECP256K1.value
        a = CURVES[curve_id].a
        b = CURVES[curve_id].b
        p = CURVES[curve_id].p
        x = bigint_pack(ids.x, 4, 2**96)
        rhs = (x**3 + a*x + b) % p
        ids.is_on_curve = is_quad_residue(rhs, p)
        if ids.is_on_curve == 1:
            square_root = sqrt_mod(rhs, p)
            if ids.v % 2 == square_root % 2:
                pass
            else:
                square_root = - square_root % p
        else:
            square_root = sqrt_mod(rhs*CURVES[curve_id].fp_generator, p)

        bigint_fill(square_root, ids.y_try, 4, 2**96)
    %}

    assert 0 = is_on_curve * (1 - is_on_curve);  // assert it's a bool
    let input: UInt384* = cast(range_check96_ptr, UInt384*);
    assert input[0] = UInt384(1, 0, 0, 0);  // constant
    assert input[1] = UInt384(0, 0, 0, 0);  // constant
    assert input[2] = x;
    assert input[3] = UInt384(secp256k1.A0, secp256k1.A1, secp256k1.A2, secp256k1.A3);
    assert input[4] = UInt384(secp256k1.B0, secp256k1.B1, secp256k1.B2, secp256k1.B3);
    assert input[5] = UInt384(secp256k1.G0, secp256k1.G1, secp256k1.G2, secp256k1.G3);
    assert input[6] = y_try;
    assert input[7] = UInt384(is_on_curve, 0, 0, 0);

    let p = UInt384(secp256k1.P0, secp256k1.P1, secp256k1.P2, secp256k1.P3);
    assert add_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=input, offsets_ptr=add_offsets_ptr, n=add_mod_n
    );
    assert mul_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=input, offsets_ptr=mul_offsets_ptr, n=mul_mod_n
    );

    %{
        from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner
        assert builtin_runners["add_mod_builtin"].instance_def.batch_size == 1
        assert builtin_runners["mul_mod_builtin"].instance_def.batch_size == 1

        ModBuiltinRunner.fill_memory(
            memory=memory,
            add_mod=(ids.add_mod_ptr.address_, builtin_runners["add_mod_builtin"], ids.add_mod_n),
            mul_mod=(ids.mul_mod_ptr.address_, builtin_runners["mul_mod_builtin"], ids.mul_mod_n),
        )
    %}

    let add_mod_ptr = &add_mod_ptr[add_mod_n];
    let mul_mod_ptr = &mul_mod_ptr[mul_mod_n];
    let range_check96_ptr = range_check96_ptr + 76;  // 72 is the last start index in the offset_ptr array

    return (y=y_try, is_on_curve=is_on_curve);

    add_offsets_ptr_loc:
    dw 40;  // ax
    dw 16;  // b
    dw 44;  // ax + b
    dw 36;  // x^3
    dw 44;  // ax + b
    dw 48;  // x^3 + ax + b (:= rhs)
    dw 28;  // is_on_curve
    dw 60;  // 1 - is_on_curve
    dw 0;  // 1
    dw 56;  // is_on_curve * rhs
    dw 64;  // (1 - is_on_curve) * g * rhs
    dw 68;  // is_on_curve * rhs + (1-is_on_curve) * g * rhs
    dw 4;  // 0
    dw 72;  // y_try^2
    dw 68;  // is_on_curve * rhs + (1-is_on_curve) * g * rhs

    mul_offsets_ptr_loc:
    dw 8;  // x
    dw 8;  // x
    dw 32;  // x^2
    dw 8;  // x
    dw 32;  // x^2
    dw 36;  // x^3
    dw 12;  // a
    dw 8;  // x
    dw 40;  // ax
    dw 20;  // g
    dw 48;  // rhs
    dw 52;  // g * rhs
    dw 28;  // is_on_curve
    dw 48;  // rhs
    dw 56;  // is_on_curve * rhs
    dw 60;  // 1 - is_on_curve
    dw 52;  // g * rhs
    dw 64;  // (1 - is_on_curve) * g * rhs
    dw 24;  // y_try
    dw 24;  // y_try
    dw 72;  // y_try^2
}

// @notice Get a random point from x
func get_random_point{
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(seed: felt) -> G1Point {
    alloc_locals;
    let x_384 = felt_to_uint384(seed);

    let (y, is_on_curve) = try_get_point_from_x(x=x_384, v=0);

    if (is_on_curve != 0) {
        let point = G1Point(x=x_384, y=y);
        return point;
    }

    assert poseidon_ptr[0].input.s0 = seed;
    assert poseidon_ptr[0].input.s1 = y.d0;  // salt
    assert poseidon_ptr[0].input.s2 = 2;
    let seed = poseidon_ptr[0].output.s0;
    tempvar poseidon_ptr = poseidon_ptr + PoseidonBuiltin.SIZE;

    return get_random_point(seed=seed);
}

// Add Double an EC point. Doesn't check if the input is on curve nor if it's the point at infinity.
func ec_double{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    p: G1Point
) -> G1Point {
    alloc_locals;

    let add_mod_n = 6;
    let (add_offsets_ptr) = get_label_location(ec_double_add_offsets_label);
    let mul_mod_n = 5;
    let (mul_offsets_ptr) = get_label_location(ec_double_mul_offsets_label);

    let input: UInt384* = cast(range_check96_ptr, UInt384*);
    assert input[0] = UInt384(3, 0, 0, 0);
    assert input[1] = p.x;
    assert input[2] = p.y;
    assert input[3] = UInt384(secp256k1.A0, secp256k1.A1, secp256k1.A2, secp256k1.A3);

    let modulus = UInt384(secp256k1.P0, secp256k1.P1, secp256k1.P2, secp256k1.P3);
    assert add_mod_ptr[0] = ModBuiltin(
        p=modulus, values_ptr=input, offsets_ptr=add_offsets_ptr, n=add_mod_n
    );
    assert mul_mod_ptr[0] = ModBuiltin(
        p=modulus, values_ptr=input, offsets_ptr=mul_offsets_ptr, n=mul_mod_n
    );

    %{
        from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner
        assert builtin_runners["add_mod_builtin"].instance_def.batch_size == 1
        assert builtin_runners["mul_mod_builtin"].instance_def.batch_size == 1

        ModBuiltinRunner.fill_memory(
            memory=memory,
            add_mod=(ids.add_mod_ptr.address_, builtin_runners["add_mod_builtin"], ids.add_mod_n),
            mul_mod=(ids.mul_mod_ptr.address_, builtin_runners["mul_mod_builtin"], ids.mul_mod_n),
        )
    %}

    let add_mod_ptr = &add_mod_ptr[add_mod_n];
    let mul_mod_ptr = &mul_mod_ptr[mul_mod_n];
    let res = G1Point(
        x=[cast(range_check96_ptr + 44, UInt384*)], y=[cast(range_check96_ptr + 56, UInt384*)]
    );
    let range_check96_ptr = range_check96_ptr + 60;  // 56 is the last start index in the offset_ptr array

    return res;

    ec_double_add_offsets_label:
    dw 20;
    dw 12;
    dw 24;
    dw 8;
    dw 8;
    dw 28;
    dw 4;
    dw 40;
    dw 36;
    dw 4;
    dw 44;
    dw 40;
    dw 44;
    dw 48;
    dw 4;
    dw 8;
    dw 56;
    dw 52;

    ec_double_mul_offsets_label:
    dw 4;
    dw 4;
    dw 16;
    dw 0;
    dw 16;
    dw 20;
    dw 28;
    dw 32;
    dw 24;
    dw 32;
    dw 32;
    dw 36;
    dw 32;
    dw 48;
    dw 52;
}

// Add two EC points. Doesn't check if the inputs are on curve nor if they are the point at infinity.
func ec_add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    p: G1Point, q: G1Point
) -> G1Point {
    alloc_locals;
    let modulus = UInt384(secp256k1.P0, secp256k1.P1, secp256k1.P2, secp256k1.P3);
    let same_x = uint384_eq_mod_p(p.x, q.x, modulus);

    if (same_x != 0) {
        let opposite_y = uint384_is_neg_mod_p(p.y, q.y, modulus);
        if (opposite_y != 0) {
            // p + (-p) = O (point at infinity)
            let res = G1Point(UInt384(0, 0, 0, 0), UInt384(0, 0, 0, 0));
            return res;
        }

        return ec_double(p);
    }

    let add_mod_n = 6;
    let (add_offsets_ptr) = get_label_location(ec_add_add_offsets_label);
    let mul_mod_n = 3;
    let (mul_offsets_ptr) = get_label_location(ec_add_mul_offsets_label);
    let input: UInt384* = cast(range_check96_ptr, UInt384*);
    assert input[0] = p.x;
    assert input[1] = p.y;
    assert input[2] = q.x;
    assert input[3] = q.y;

    assert add_mod_ptr[0] = ModBuiltin(
        p=modulus, values_ptr=input, offsets_ptr=add_offsets_ptr, n=add_mod_n
    );
    assert mul_mod_ptr[0] = ModBuiltin(
        p=modulus, values_ptr=input, offsets_ptr=mul_offsets_ptr, n=mul_mod_n
    );

    %{
        from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner
        assert builtin_runners["add_mod_builtin"].instance_def.batch_size == 1
        assert builtin_runners["mul_mod_builtin"].instance_def.batch_size == 1

        ModBuiltinRunner.fill_memory(
            memory=memory,
            add_mod=(ids.add_mod_ptr.address_, builtin_runners["add_mod_builtin"], ids.add_mod_n),
            mul_mod=(ids.mul_mod_ptr.address_, builtin_runners["mul_mod_builtin"], ids.mul_mod_n),
        )
    %}

    let add_mod_ptr = &add_mod_ptr[add_mod_n];
    let mul_mod_ptr = &mul_mod_ptr[mul_mod_n];
    let range_check96_ptr = range_check96_ptr + 52;  // 48 is the last start index in the offset_ptr array

    let res = G1Point(
        x=[cast(cast(input, felt*) + 36, UInt384*)], y=[cast(cast(input, felt*) + 48, UInt384*)]
    );
    return res;

    ec_add_add_offsets_label:
    dw 12;
    dw 16;
    dw 4;
    dw 8;
    dw 20;
    dw 0;
    dw 0;
    dw 32;
    dw 28;
    dw 8;
    dw 36;
    dw 32;
    dw 36;
    dw 40;
    dw 0;
    dw 4;
    dw 48;
    dw 44;

    ec_add_mul_offsets_label:
    dw 20;
    dw 24;
    dw 16;
    dw 24;
    dw 24;
    dw 28;
    dw 24;
    dw 40;
    dw 44;
}

@known_ap_change
func sign_to_uint384_mod_secp256k1(sign: felt) -> UInt384 {
    if (sign == -1) {
        let res = UInt384(
            secp256k1.MIN_ONE_D0, secp256k1.MIN_ONE_D1, secp256k1.MIN_ONE_D2, secp256k1.MIN_ONE_D3
        );
        return res;
    } else {
        let res = UInt384(1, 0, 0, 0);
        return res;
    }
}

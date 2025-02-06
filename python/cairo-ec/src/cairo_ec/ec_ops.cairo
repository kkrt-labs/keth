from starkware.cairo.common.cairo_builtins import UInt384, ModBuiltin, PoseidonBuiltin
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc

from cairo_ec.curve.g1_point import G1Point
from cairo_ec.uint384 import uint384_is_neg_mod_p, uint384_eq_mod_p, felt_to_uint384
from cairo_ec.circuits.ec_ops_compiled import assert_is_on_curve

// @notice Try to get the point from x.
// @return y The y point such that (x, y) is on the curve if success is 1, otherwise (g*h, y) is on the curve
// @return is_on_curve 1 if the point is on the curve, 0 otherwise
// @dev g is the generator point and h is the hash of the message
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

    assert_is_on_curve(x=x, y=&y_try, a=a, b=b, g=g, is_on_curve=&is_on_curve, p=p);
    assert is_on_curve.d3 = 0;
    assert is_on_curve.d2 = 0;
    assert is_on_curve.d1 = 0;
    // TODO: Add a check for v

    return (y=&y_try, is_on_curve=is_on_curve.d0);
}

// @notice Get a random point from x
func get_random_point{
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(seed: felt, a: UInt384*, b: UInt384*, g: UInt384*, p: UInt384*) -> G1Point {
    alloc_locals;
    let (__fp__, __pc__) = get_fp_and_pc();
    let x_384 = felt_to_uint384(seed);
    tempvar x = new x_384;

    local is_on_curve: UInt384;
    local y_try: UInt384;
    tempvar v = 0;
    %{ compute_y_from_x_hint %}

    assert_is_on_curve(x=x, y=&y_try, a=a, b=b, g=g, is_on_curve=&is_on_curve, p=p);

    assert is_on_curve.d3 = 0;
    assert is_on_curve.d2 = 0;
    assert is_on_curve.d1 = 0;

    if (is_on_curve.d0 != 0) {
        let point = G1Point(x=x_384, y=y_try);
        return point;
    }

    assert poseidon_ptr[0].input.s0 = seed;
    assert poseidon_ptr[0].input.s1 = y_try.d0;  // salt
    assert poseidon_ptr[0].input.s2 = 2;
    let seed = poseidon_ptr[0].output.s0;
    tempvar poseidon_ptr = poseidon_ptr + PoseidonBuiltin.SIZE;

    return get_random_point(seed=seed, a=a, b=b, g=g, p=p);
}

// Add Double an EC point. Doesn't check if the input is on curve nor if it's the point at infinity.
func ec_double{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    p: G1Point, g: UInt384, a: UInt384, modulus: UInt384
) -> G1Point {
    alloc_locals;

    let add_mod_n = 6;
    let (add_offsets_ptr) = get_label_location(ec_double_add_offsets_label);
    let mul_mod_n = 5;
    let (mul_offsets_ptr) = get_label_location(ec_double_mul_offsets_label);

    let input: UInt384* = cast(range_check96_ptr, UInt384*);
    assert input[0] = g;
    assert input[1] = p.x;
    assert input[2] = p.y;
    assert input[3] = a;

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
    p: G1Point, q: G1Point, g: UInt384, a: UInt384, modulus: UInt384
) -> G1Point {
    alloc_locals;
    let same_x = uint384_eq_mod_p(p.x, q.x, modulus);

    if (same_x != 0) {
        let opposite_y = uint384_is_neg_mod_p(p.y, q.y, modulus);
        if (opposite_y != 0) {
            // p + (-p) = O (point at infinity)
            let res = G1Point(UInt384(0, 0, 0, 0), UInt384(0, 0, 0, 0));
            return res;
        }

        return ec_double(p, g, a, modulus);
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

// Multiply an EC point by a scalar. Doesn't check if the input is on curve nor if it's the point at infinity.
func ec_mul{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    p: G1Point, scalar: UInt384, g: UInt384, a: UInt384, modulus: UInt384
) -> G1Point {
    // TODO: Implement this function.
    let res = G1Point(UInt384(0, 0, 0, 0), UInt384(0, 0, 0, 0));
    return res;
}

from starkware.cairo.common.cairo_builtins import UInt384, ModBuiltin
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.uint256 import Uint256

from cairo_core.maths import unsigned_div_rem

const STARK_MIN_ONE_D2 = 0x800000000000011;

func felt_to_uint384{range_check96_ptr: felt*}(x: felt) -> UInt384 {
    let d0 = [range_check96_ptr];
    let d1 = [range_check96_ptr + 1];
    let d2 = [range_check96_ptr + 2];
    %{ felt_to_uint384_split_hint %}
    assert [range_check96_ptr + 3] = STARK_MIN_ONE_D2 - d2;
    assert x = d0 + d1 * 2 ** 96 + d2 * 2 ** 192;

    if (d2 == STARK_MIN_ONE_D2) {
        // STARK_MIN_ONE = 0x800000000000011000000000000000000000000000000000000000000000000
        // So d0 = 0, d1 = 0, d2 = 0x800000000000011
        // If d2 == STARK_MIN_ONE_D2, then d0 == 0 and d1 == 0
        assert d0 = 0;
        assert d1 = 0;
    }

    tempvar range_check96_ptr = range_check96_ptr + 4;
    let res = UInt384(d0, d1, d2, 0);
    return res;
}

// @notice Converts a 256-bit unsigned integer to a 384-bit unsigned integer.
// @param a The 256-bit unsigned integer.
// @return res The resulting 384-bit unsigned integer.
func uint256_to_uint384{range_check_ptr}(a: Uint256) -> UInt384 {
    let (high_64_high, high_64_low) = unsigned_div_rem(a.high, 2 ** 64);
    let (low_32_high, low_96_low) = unsigned_div_rem(a.low, 2 ** 96);
    let res = UInt384(low_96_low, low_32_high + 2 ** 32 * high_64_low, high_64_high, 0);
    return res;
}

// @notice Converts a 384-bit unsigned integer to a 256-bit unsigned integer.
// @dev Raises if it doesn't fit in 256 bits.
// @param a The 384-bit unsigned integer.
// @return res The resulting 256-bit unsigned integer.
func uint384_to_uint256{range_check_ptr}(a: UInt384) -> Uint256 {
    assert a.d3 = 0;
    let (d2_high, d2_low) = unsigned_div_rem(a.d2, 2 ** 64);
    assert d2_high = 0;
    let (d1_high, d1_low) = unsigned_div_rem(a.d1, 2 ** 32);
    let res = Uint256(low=a.d0 + 2 ** 96 * d1_low, high=d1_high + 2 ** 64 * d2_low);
    return res;
}

// @notice Asserts that a 384-bit unsigned integer is less than or equal to another 384-bit unsigned integer.
// @param a The first 384-bit unsigned integer.
// @param b The second 384-bit unsigned integer.
func uint384_assert_le{range_check96_ptr: felt*}(a: UInt384, b: UInt384) {
    assert [range_check96_ptr + 0] = b.d3 - a.d3;
    if (b.d3 != a.d3) {
        let range_check96_ptr = range_check96_ptr + 1;
        return ();
    }
    assert [range_check96_ptr + 1] = b.d2 - a.d2;
    if (b.d2 != a.d2) {
        let range_check96_ptr = range_check96_ptr + 2;
        return ();
    }
    assert [range_check96_ptr + 2] = b.d1 - a.d1;
    if (b.d1 != a.d1) {
        let range_check96_ptr = range_check96_ptr + 3;
        return ();
    }
    assert [range_check96_ptr + 3] = b.d0 - a.d0;
    let range_check96_ptr = range_check96_ptr + 4;
    return ();
}

// Assert X == Y mod p by asserting X + 0 == Y
func uint384_assert_eq_mod_p{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*}(
    x: UInt384, y: UInt384, p: UInt384
) {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_offsets_ptr = pc + (add_offsets - pc_label);

    // 0 (4)
    assert [range_check96_ptr + 0] = 0;
    assert [range_check96_ptr + 1] = 0;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;
    // X limbs (4)
    assert [range_check96_ptr + 4] = x.d0;
    assert [range_check96_ptr + 5] = x.d1;
    assert [range_check96_ptr + 6] = x.d2;
    assert [range_check96_ptr + 7] = x.d3;
    // Y limbs (8)
    assert [range_check96_ptr + 8] = y.d0;
    assert [range_check96_ptr + 9] = y.d1;
    assert [range_check96_ptr + 10] = y.d2;
    assert [range_check96_ptr + 11] = y.d3;

    assert add_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=add_offsets_ptr, n=1
    );
    %{
        from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner
        assert builtin_runners["add_mod_builtin"].instance_def.batch_size == 1

        ModBuiltinRunner.fill_memory(
            memory=memory,
            add_mod=(ids.add_mod_ptr.address_, builtin_runners["add_mod_builtin"], 1),
            mul_mod=None,
        )
    %}
    let range_check96_ptr = range_check96_ptr + 12;
    let add_mod_ptr = add_mod_ptr + ModBuiltin.SIZE;
    return ();

    add_offsets:
    dw 0;  // X
    dw 4;  // 0
    dw 8;  // X + 0 = Y
}

// @notice assert X != Y mod p by asserting (X-Y) != 0
// @dev Uses the add_mod builtin to compute X-Y % P, then mul_mod builtin to compute (X-Y)^-1 % P
func uint384_assert_neq_mod_p{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(x: UInt384, y: UInt384, p: UInt384) {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_offsets_ptr = pc + (mul_offsets - pc_label);
    // X limbs. (0)
    assert [range_check96_ptr + 0] = x.d0;
    assert [range_check96_ptr + 1] = x.d1;
    assert [range_check96_ptr + 2] = x.d2;
    assert [range_check96_ptr + 3] = x.d3;
    // Y limbs. (4)
    assert [range_check96_ptr + 4] = y.d0;
    assert [range_check96_ptr + 5] = y.d1;
    assert [range_check96_ptr + 6] = y.d2;
    assert [range_check96_ptr + 7] = y.d3;
    // X-Y % P (8)

    // 1 (12)
    assert [range_check96_ptr + 12] = 1;
    assert [range_check96_ptr + 13] = 0;
    assert [range_check96_ptr + 14] = 0;
    assert [range_check96_ptr + 15] = 0;
    // [X-Y]^-1 (16)

    assert add_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=add_offsets_ptr, n=1
    );
    assert mul_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=mul_offsets_ptr, n=1
    );
    %{ fill_add_mod_mul_mod_builtin_batch_one %}
    let range_check96_ptr = range_check96_ptr + 20;
    let add_mod_ptr = add_mod_ptr + ModBuiltin.SIZE;
    let mul_mod_ptr = mul_mod_ptr + ModBuiltin.SIZE;
    return ();

    add_offsets:
    dw 4;  // a = Y
    dw 8;  // b = X - Y
    dw 0;  // a + b = X

    mul_offsets:
    dw 8;  // a = X-Y
    dw 16;  // b = (X-Y)^-1
    dw 12;  // a * b = 1
}

// Returns 1 if X == Y mod p, 0 otherwise.
func uint384_eq_mod_p{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384, y: UInt384, p: UInt384
) -> felt {
    tempvar x_mod_p_eq_y_mod_p;
    %{ x_mod_p_eq_y_mod_p_hint %}

    if (x_mod_p_eq_y_mod_p != 0) {
        uint384_assert_eq_mod_p(x, y, p);
        return 1;
    } else {
        uint384_assert_neq_mod_p(x, y, p);
        return 0;
    }
}

// Assert X == - Y mod p by asserting X + Y == 0
func uint384_assert_neg_mod_p{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*}(
    x: UInt384, y: UInt384, p: UInt384
) {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_offsets_ptr = pc + (add_offsets - pc_label);

    // X limbs.
    assert [range_check96_ptr + 0] = x.d0;
    assert [range_check96_ptr + 1] = x.d1;
    assert [range_check96_ptr + 2] = x.d2;
    assert [range_check96_ptr + 3] = x.d3;
    // Y limbs.
    assert [range_check96_ptr + 4] = y.d0;
    assert [range_check96_ptr + 5] = y.d1;
    assert [range_check96_ptr + 6] = y.d2;
    assert [range_check96_ptr + 7] = y.d3;
    // 0
    assert [range_check96_ptr + 8] = 0;
    assert [range_check96_ptr + 9] = 0;
    assert [range_check96_ptr + 10] = 0;
    assert [range_check96_ptr + 11] = 0;

    assert add_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=add_offsets_ptr, n=1
    );
    %{ fill_add_mod_mul_mod_builtin_batch_one %}

    let range_check96_ptr = range_check96_ptr + 12;
    let add_mod_ptr = add_mod_ptr + ModBuiltin.SIZE;
    return ();

    add_offsets:
    dw 0;  // X
    dw 4;  // Y
    dw 8;  // 0
}

// assert X != -Y mod p by asserting X + Y != 0
func uint384_assert_not_neg_mod_p{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(x: UInt384, y: UInt384, p: UInt384) {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_offsets_ptr = pc + (mul_offsets - pc_label);

    // X limbs. (0)
    assert [range_check96_ptr + 0] = x.d0;
    assert [range_check96_ptr + 1] = x.d1;
    assert [range_check96_ptr + 2] = x.d2;
    assert [range_check96_ptr + 3] = x.d3;
    // Y limbs. (4)
    assert [range_check96_ptr + 4] = y.d0;
    assert [range_check96_ptr + 5] = y.d1;
    assert [range_check96_ptr + 6] = y.d2;
    assert [range_check96_ptr + 7] = y.d3;
    // X + Y (8)
    // [X+Y]^-1 (12)

    // 1 (16)
    assert [range_check96_ptr + 16] = 1;
    assert [range_check96_ptr + 17] = 0;
    assert [range_check96_ptr + 18] = 0;
    assert [range_check96_ptr + 19] = 0;

    assert add_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=add_offsets_ptr, n=1
    );
    assert mul_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=mul_offsets_ptr, n=1
    );
    %{ fill_add_mod_mul_mod_builtin_batch_one %}
    let range_check96_ptr = range_check96_ptr + 20;
    let add_mod_ptr = add_mod_ptr + ModBuiltin.SIZE;
    let mul_mod_ptr = mul_mod_ptr + ModBuiltin.SIZE;
    return ();

    add_offsets:
    dw 0;  // X
    dw 4;  // Y
    dw 8;  // X + Y

    mul_offsets:
    dw 8;  // X + Y
    dw 12;  // [X+Y]^-1
    dw 16;  // 1
}

// Returns 1 if X == -Y mod p, 0 otherwise.
func uint384_is_neg_mod_p{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(x: UInt384, y: UInt384, p: UInt384) -> felt {
    tempvar x_is_neg_y_mod_p;
    %{ x_is_neg_y_mod_p_hint %}
    if (x_is_neg_y_mod_p != 0) {
        uint384_assert_neg_mod_p(x, y, p);
        return 1;
    } else {
        uint384_assert_not_neg_mod_p(x, y, p);
        return 0;
    }
}

// Compute X / Y mod p.
func uint384_div_mod_p{range_check96_ptr: felt*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384, y: UInt384, p: UInt384
) -> UInt384 {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let mul_offsets_ptr = pc + (mul_offsets - pc_label);

    // X limbs (offset 0)
    assert [range_check96_ptr + 0] = x.d0;
    assert [range_check96_ptr + 1] = x.d1;
    assert [range_check96_ptr + 2] = x.d2;
    assert [range_check96_ptr + 3] = x.d3;
    // Y limbs (offset 4)
    assert [range_check96_ptr + 4] = y.d0;
    assert [range_check96_ptr + 5] = y.d1;
    assert [range_check96_ptr + 6] = y.d2;
    assert [range_check96_ptr + 7] = y.d3;

    assert mul_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=mul_offsets_ptr, n=1
    );
    %{ fill_add_mod_mul_mod_builtin_batch_one %}

    let range_check96_ptr = range_check96_ptr + 12;
    let mul_mod_ptr = mul_mod_ptr + ModBuiltin.SIZE;
    return [cast(range_check96_ptr - 4, UInt384*)];

    mul_offsets:
    dw 4;  // Y
    dw 8;  // X/Y
    dw 0;  // X
}

// Compute - Y mod p.
func uint384_neg_mod_p{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*}(
    y: UInt384, p: UInt384
) -> UInt384 {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_offsets_ptr = pc + (add_offsets - pc_label);

    // X limbs (offset 0)
    assert [range_check96_ptr] = 0;
    assert [range_check96_ptr + 1] = 0;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;
    // Y limbs (offset 4)
    assert [range_check96_ptr + 4] = y.d0;
    assert [range_check96_ptr + 5] = y.d1;
    assert [range_check96_ptr + 6] = y.d2;
    assert [range_check96_ptr + 7] = y.d3;

    assert add_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=add_offsets_ptr, n=1
    );
    %{ fill_add_mod_mul_mod_builtin_batch_one %}

    let range_check96_ptr = range_check96_ptr + 12;
    let add_mod_ptr = add_mod_ptr + ModBuiltin.SIZE;
    return [cast(range_check96_ptr - 4, UInt384*)];

    add_offsets:
    dw 4;  // Y
    dw 8;  // -Y
    dw 0;  // 0
}

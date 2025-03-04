from starkware.cairo.common.cairo_builtins import UInt384, ModBuiltin
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.uint256 import Uint256

from cairo_core.maths import unsigned_div_rem
from cairo_ec.circuits.mod_ops_compiled import (
    assert_eq,
    assert_neq,
    neg,
    assert_neg,
    assert_not_neg,
    div,
)

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

// Returns 1 if X == Y, 0 otherwise.
func uint384_eq{range_check96_ptr: felt*}(x: UInt384, y: UInt384) -> felt {
    if (x.d0 == y.d0 and x.d1 == y.d1 and x.d2 == y.d2 and x.d3 == y.d3) {
        return 1;
    }
    return 0;
}

// Returns 1 if X == Y mod p, 0 otherwise.
func uint384_eq_mod_p{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384, y: UInt384, p: UInt384
) -> felt {
    tempvar x_mod_p_eq_y_mod_p;
    %{ x_mod_p_eq_y_mod_p_hint %}

    if (x_mod_p_eq_y_mod_p != 0) {
        assert_eq(new x, new y, new p);
        return 1;
    } else {
        assert_neq(new x, new y, new p);
        return 0;
    }
}

// Returns 1 if X == -Y mod p, 0 otherwise.
func uint384_is_neg_mod_p{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(x: UInt384, y: UInt384, p: UInt384) -> felt {
    tempvar x_is_neg_y_mod_p;
    %{ x_is_neg_y_mod_p_hint %}
    if (x_is_neg_y_mod_p != 0) {
        assert_neg(new x, new y, new p);
        return 1;
    } else {
        assert_not_neg(new x, new y, new p);
        return 0;
    }
}

// Returns x % p
// It does not assert that x is in [0, p), nor if the computed value is effectively equal to x mod p.
func uint384_div_rem{}(x: UInt384, p: UInt384) -> (UInt384, UInt384) {
    tempvar q: UInt384;
    tempvar r: UInt384;
    %{ div_rem_hint %}
    return (q, r);
}

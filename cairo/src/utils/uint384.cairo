from starkware.cairo.common.cairo_builtins import UInt384
from starkware.cairo.common.uint256 import Uint256
from ethereum.utils.numeric import divmod

// @notice Converts a 256-bit unsigned integer to a 384-bit unsigned integer.
// @param a The 256-bit unsigned integer.
// @return res The resulting 384-bit unsigned integer.
func uint256_to_uint384{range_check_ptr}(a: Uint256) -> UInt384 {
    let (high_64_high, high_64_low) = divmod(a.high, 2 ** 64);
    let (low_32_high, low_96_low) = divmod(a.low, 2 ** 96);
    let res = UInt384(low_96_low, low_32_high + 2 ** 32 * high_64_low, high_64_high, 0);
    return res;
}

// @notice Converts a 384-bit unsigned integer to a 256-bit unsigned integer.
// @dev Raises if it doesn't fit in 256 bits.
// @param a The 384-bit unsigned integer.
// @return res The resulting 256-bit unsigned integer.
func uint384_to_uint256{range_check_ptr}(a: UInt384) -> Uint256 {
    assert a.d3 = 0;
    let (d2_high, d2_low) = divmod(a.d2, 2 ** 64);
    assert d2_high = 0;
    let (d1_high, d1_low) = divmod(a.d1, 2 ** 32);
    let res = Uint256(low=a.d0 + 2 ** 96 * d1_low, high=d1_high + 2 ** 64 * d2_low);
    return res;
}

// @notice Asserts that a 384-bit unsigned integer is less than or equal to another 384-bit unsigned integer.
// @param a The first 384-bit unsigned integer.
// @param b The second 384-bit unsigned integer.
func assert_uint384_le{range_check96_ptr: felt*}(a: UInt384, b: UInt384) {
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

from cairo_core.numeric import bool

@known_ap_change
func is_zero(value) -> felt {
    if (value == 0) {
        return 1;
    }

    return 0;
}

@known_ap_change
func is_not_zero(value) -> felt {
    if (value != 0) {
        return 1;
    }

    return 0;
}

// Returns 1 if lhs <= rhs (or more precisely 0 <= rhs - lhs < RANGE_CHECK_BOUND).
// Returns 0 otherwise.
// Soundness assumptions (caller responsibility to ensure those) :
// - 0 <= lhs < RANGE_CHECK_BOUND
// - 0 <= rhs < RANGE_CHECK_BOUND
@known_ap_change
func is_le_unchecked{range_check_ptr}(lhs: felt, rhs: felt) -> felt {
    tempvar a = rhs - lhs;  // reference (rhs-lhs) as "a" to use already whitelisted hint
    %{ memory[ap] = 0 if 0 <= (ids.a % PRIME) < range_check_builtin.bound else 1 %}
    jmp false if [ap] != 0, ap++;

    // Ensure lhs <= rhs
    assert [range_check_ptr] = a;
    ap += 2;  // Two memory holes for known_ap_change in case of false case: Two instructions more: -1*a, and (-1*a) - 1.
    tempvar range_check_ptr = range_check_ptr + 1;
    tempvar res = 1;
    ret;

    false:
    // Ensure rhs < lhs
    assert [range_check_ptr] = (-a) - 1;
    tempvar range_check_ptr = range_check_ptr + 1;
    tempvar res = 0;
    ret;
}

// TODO: this is not the best approach, considering that the non-equal case is hard to prove,
// and thus, we should think of a better approach.
// @notice Tries to check if two pointers are equal. This can be trusted if the pointers are equal, but
// cannot be trusted if they are not equal. Thus, use carefully.
// @dev Returns 1 if lhs and rhs point to the same memory location, 0 otherwise
//      A typical `lhs == rhs` comparison will fail if both pointers don't have the same segment index.
//      We can ask the prover to provide whether they are equal, and simply verify this result.
// @param lhs The first pointer to compare
// @param rhs The second pointer to compare
// @return (1, 1) if pointers are equal, (0, 1) if they're not equal, (0, 0) if we cannot attest their equality.
func is_ptr_equal(lhs: felt*, rhs: felt*) -> (bool, bool) {
    alloc_locals;

    if (cast(lhs, felt) == 0) {
        if (cast(rhs, felt) == 0) {
            let res = (bool(1), bool(1));
            return res;
        }
        let res = (bool(0), bool(1));
        return res;
    }

    tempvar segment_equal;
    %{ ids.segment_equal = (ids.lhs.segment_index == ids.rhs.segment_index) %}
    jmp segments_are_equal if segment_equal != 0, ap++;

    // We can prove the equality, but not the inequality on different segments.
    let res = (bool(0), bool(0));
    return res;

    segments_are_equal:
    let res_ = is_zero(lhs - rhs);
    let res = (bool(res_), bool(1));
    return res;
}

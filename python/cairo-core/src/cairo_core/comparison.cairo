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

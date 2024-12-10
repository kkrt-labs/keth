from starkware.cairo.common.math_cmp import is_le, is_not_zero
from ethereum_types.numeric import Uint

func min{range_check_ptr}(a: felt, b: felt) -> felt {
    if (a == b) {
        return a;
    }

    let res = is_le(a, b);
    if (res == 1) {
        return a;
    }
    return b;
}

func max{range_check_ptr}(a: felt, b: felt) -> felt {
    if (a == b) {
        return a;
    }

    let res = is_le(b, a);
    if (res == 1) {
        return a;
    }
    return b;
}

@known_ap_change
func is_zero(value) -> felt {
    if (value == 0) {
        return 1;
    }

    return 0;
}

// @dev Inlined version of unsigned_div_rem
// Returns q and r such that:
//  0 <= q < rc_bound, 0 <= r < div and value = q * div + r.
//
// Assumption: 0 < div <= PRIME / rc_bound.
// Prover assumption: value / div < rc_bound.
//
// The value of div is restricted to make sure there is no overflow.
// q * div + r < (q + 1) * div <= rc_bound * (PRIME / rc_bound) = PRIME.
func divmod{range_check_ptr}(value, div) -> (q: felt, r: felt) {
    let r = [range_check_ptr];
    let q = [range_check_ptr + 1];
    let range_check_ptr = range_check_ptr + 2;
    %{
        from starkware.cairo.common.math_utils import assert_integer
        assert_integer(ids.div)
        assert 0 < ids.div <= PRIME // range_check_builtin.bound, \
            f'div={hex(ids.div)} is out of the valid range.'
        ids.q, ids.r = divmod(ids.value, ids.div)
    %}

    // equivalent to assert_le(r, div - 1);
    tempvar a = div - 1 - r;
    %{
        from starkware.cairo.common.math_utils import assert_integer
        assert_integer(ids.a)
        assert 0 <= ids.a % PRIME < range_check_builtin.bound, f'a = {ids.a} is out of range.'
    %}
    a = [range_check_ptr];
    let range_check_ptr = range_check_ptr + 1;

    assert value = q * div + r;
    return (q, r);
}

func ceil32{range_check_ptr}(value: Uint) -> Uint {
    let ceiling = 32;
    let (_, remainder) = divmod(value.value, ceiling);
    if (remainder == 0) {
        return value;
    }
    let result = Uint(value.value + 32 - remainder);
    return result;
}

func taylor_exponential{range_check_ptr}(factor: Uint, numerator: Uint, denominator: Uint) -> Uint {
    let output = 0;
    let i = 1;
    let numerator_accumulated = factor.value * denominator.value;
    let value = _taylor_exponential(
        output, i, numerator_accumulated, numerator.value, denominator.value
    );
    let result = Uint(value);
    return result;
}

func _taylor_exponential{range_check_ptr}(
    output: felt, i: felt, numerator_accumulated: felt, numerator: felt, denominator: felt
) -> felt {
    let cond = is_not_zero(numerator_accumulated);
    if (cond == 0) {
        let (res, _) = divmod(output, denominator);
        return res;
    }

    let output = output + numerator_accumulated;
    let value = numerator_accumulated * numerator;
    let div = denominator * i;
    let (numerator_accumulated, _) = divmod(value, div);
    let i = i + 1;

    return _taylor_exponential(output, i, numerator_accumulated, numerator, denominator);
}

from starkware.cairo.common.math import assert_le_felt

// @dev Inlined version of unsigned_div_rem
// Returns q and r such that:
//  0 <= q < rc_bound, 0 <= r < div and value = q * div + r.
//
// Assumption: 0 < div <= PRIME / rc_bound.
// Prover assumption: value / div < rc_bound.
//
// The value of div is restricted to make sure there is no overflow.
// q * div + r < (q + 1) * div <= rc_bound * (PRIME / rc_bound) = PRIME.
func unsigned_div_rem{range_check_ptr}(value, div) -> (q: felt, r: felt) {
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

func ceil32{range_check_ptr}(value: felt) -> felt {
    if (value == 0) {
        return 0;
    }
    let (q, r) = unsigned_div_rem(value + 31, 32);
    return q * 32;
}

// Returns the sign of value: -1 if value < 0, 1 if value > 0.
// value is considered positive if it is in [0, STARK//2[
// value is considered negative if it is in ]STARK//2, STARK[
// If value == 0, returned value can be either 0 or 1 (undetermined).
func sign{range_check_ptr}(value) -> felt {
    const STARK_DIV_2_PLUS_ONE = (-1) / 2 + 1;  // == prime//2 + 1
    const STARK_DIV_2_MIN_ONE = (-1) / 2 - 1;  // == prime//2 - 1
    tempvar is_positive: felt;
    %{
        from starkware.cairo.common.math_utils import as_int
        ids.is_positive = 1 if as_int(ids.value, PRIME) >= 0 else 0
    %}
    if (is_positive != 0) {
        assert_le_felt(value, STARK_DIV_2_MIN_ONE);
        return 1;
    } else {
        assert_le_felt(STARK_DIV_2_PLUS_ONE, value);
        return -1;
    }
}

// @notice Decompose a 128 bit scalar into base (-3) with coefficients in {-1, 0, 1},
//         also called "extended positive-negative sum" representation
//         scalar = sum(digits[i] * (-3)^i for i in [0, 81])
//         digits[i] in {-1, 0, 1} for all i
//         scalar = sum_p - sum_n
//         sum_p = sum(digits[i] * (-3)^i for i in [0, 81] if digits[i]==1)
//         sum_n = sum(digits[i] * (-3)^i for i in [0, 81] if digits[i]==-1)
// @returns (abs(sum_p), abs(sum_n), p_sign, n_sign)
func scalar_to_epns{range_check_ptr}(scalar: felt) -> (
    sum_p: felt, sum_n: felt, p_sign: felt, n_sign: felt
) {
    %{
        from garaga.hints.neg_3 import neg_3_base_le, positive_negative_multiplicities
        from starkware.cairo.common.math_utils import as_int
        assert 0 <= ids.scalar < 2**128
        digits = neg_3_base_le(ids.scalar)
        digits = digits + [0] * (82-len(digits))
        i=1 # Loop init
    %}

    tempvar d0;
    %{ ids.d0 = digits[0] %}

    if (d0 != 0) {
        if (d0 == 1) {
            tempvar sum_p = 1;
            tempvar sum_n = 0;
        } else {
            tempvar sum_p = 0;
            tempvar sum_n = 1;
        }
    } else {
        tempvar sum_p = 0;
        tempvar sum_n = 0;
    }

    tempvar pow3 = -3;

    loop:
    let sum_p = [ap - 3];
    let sum_n = [ap - 2];
    let pow3 = [ap - 1];
    %{ memory[ap] = 1 if i == 82 else 0 %}
    jmp end if [ap] != 0, ap++;

    %{ i+=1 %}

    tempvar di;
    %{ ids.di = digits[i-1] %}
    if (di != 0) {
        if (di == 1) {
            tempvar sum_p = sum_p + pow3;
            tempvar sum_n = sum_n;
            tempvar pow3 = pow3 * (-3);
            jmp loop;
        } else {
            tempvar sum_p = sum_p;
            tempvar sum_n = sum_n + pow3;
            tempvar pow3 = pow3 * (-3);
            jmp loop;
        }
    } else {
        tempvar sum_p = sum_p;
        tempvar sum_n = sum_n;
        tempvar pow3 = pow3 * (-3);
        jmp loop;
    }

    end:
    let sum_p = [ap - 4];
    let sum_n = [ap - 3];
    let pow3 = [ap - 2];
    assert pow3 = (-3) ** 82;

    assert scalar = sum_p - sum_n;

    let p_sign = sign(sum_p);
    let n_sign = sign(sum_n);

    return (p_sign * sum_p, n_sign * sum_n, p_sign, n_sign);
}

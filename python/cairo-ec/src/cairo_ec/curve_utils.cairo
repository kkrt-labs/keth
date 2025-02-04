from cairo_core.maths import sign

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
    %{ decompose_scalar_to_neg3_base %}

    tempvar d0;
    %{ digit_zero_hint %}

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
    %{ set_ap_true_if_i_82 %}
    jmp end if [ap] != 0, ap++;

    %{ increment_i_hint %}

    tempvar di;
    %{ digit_i_hint %}
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

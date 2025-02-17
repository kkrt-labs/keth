from cairo_core.maths import sign
from cairo_core.comparison import is_zero
from starkware.cairo.common.alloc import alloc

// @notice Decompose a 128 bit scalar into base (-3) with coefficients in {-1, 0, 1},
//         also called "extended positive-negative sum" representation
//         scalar = sum(digits[i] * (-3)^i for i in [0, 81])
//         digits[i] in {-1, 0, 1} for all i
//         scalar = sum_p - sum_n
//         sum_p = sum(digits[i] * (-3)^i for i in [0, 81] if digits[i]==1)
//         sum_n = sum(digits[i] * (-3)^i for i in [0, 81] if digits[i]==-1)
// @returns (abs(sum_p), abs(sum_n), p_sign, n_sign)
// TODO: in the RustVM, we can't leverage hints as much as we'd like to handle the control flow.
// the intermediate variables (i, digits) could be simply provided by a hint - which is more efficient
func scalar_to_epns{range_check_ptr}(scalar: felt) -> (
    sum_p: felt, sum_n: felt, p_sign: felt, n_sign: felt
) {
    alloc_locals;
    let (local digits: felt*) = alloc();
    tempvar d0;
    %{ decompose_scalar_to_neg3_base %}
    ap += 1;
    let i = [ap - 1];

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
    tempvar i = i;

    loop:
    let sum_p = [ap - 4];
    let sum_n = [ap - 3];
    let pow3 = [ap - 2];
    let i = [ap - 1];
    let is_82 = is_zero(i - 82);

    static_assert sum_p == [ap - 8];
    static_assert sum_n == [ap - 7];
    static_assert pow3 == [ap - 6];
    static_assert i == [ap - 5];
    jmp end if is_82 != 0;

    let i = i + 1;

    tempvar di = digits[i - 1];
    if (di != 0) {
        if (di == 1) {
            tempvar sum_p = sum_p + pow3;
            tempvar sum_n = sum_n;
            tempvar pow3 = pow3 * (-3);
            tempvar i = i;
            jmp loop;
        } else {
            tempvar sum_p = sum_p;
            tempvar sum_n = sum_n + pow3;
            tempvar pow3 = pow3 * (-3);
            tempvar i = i;
            jmp loop;
        }
    } else {
        tempvar sum_p = sum_p;
        tempvar sum_n = sum_n;
        tempvar pow3 = pow3 * (-3);
        tempvar i = i;
        jmp loop;
    }

    end:
    let sum_p = [ap - 8];
    let sum_n = [ap - 7];
    let pow3 = [ap - 6];
    let i = [ap - 5];
    assert pow3 = (-3) ** 82;

    assert scalar = sum_p - sum_n;

    let p_sign = sign(sum_p);
    let n_sign = sign(sum_n);

    return (p_sign * sum_p, n_sign * sum_n, p_sign, n_sign);
}

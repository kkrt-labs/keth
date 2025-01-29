from starkware.cairo.common.math import assert_le_felt
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.common.uint256 import Uint256

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

func pow2(i: felt) -> (res: felt) {
    let (data_address) = get_label_location(data);
    return (res=[data_address + i]);

    data:
    dw 2 ** 0;
    dw 2 ** 1;
    dw 2 ** 2;
    dw 2 ** 3;
    dw 2 ** 4;
    dw 2 ** 5;
    dw 2 ** 6;
    dw 2 ** 7;
    dw 2 ** 8;
    dw 2 ** 9;
    dw 2 ** 10;
    dw 2 ** 11;
    dw 2 ** 12;
    dw 2 ** 13;
    dw 2 ** 14;
    dw 2 ** 15;
    dw 2 ** 16;
    dw 2 ** 17;
    dw 2 ** 18;
    dw 2 ** 19;
    dw 2 ** 20;
    dw 2 ** 21;
    dw 2 ** 22;
    dw 2 ** 23;
    dw 2 ** 24;
    dw 2 ** 25;
    dw 2 ** 26;
    dw 2 ** 27;
    dw 2 ** 28;
    dw 2 ** 29;
    dw 2 ** 30;
    dw 2 ** 31;
    dw 2 ** 32;
    dw 2 ** 33;
    dw 2 ** 34;
    dw 2 ** 35;
    dw 2 ** 36;
    dw 2 ** 37;
    dw 2 ** 38;
    dw 2 ** 39;
    dw 2 ** 40;
    dw 2 ** 41;
    dw 2 ** 42;
    dw 2 ** 43;
    dw 2 ** 44;
    dw 2 ** 45;
    dw 2 ** 46;
    dw 2 ** 47;
    dw 2 ** 48;
    dw 2 ** 49;
    dw 2 ** 50;
    dw 2 ** 51;
    dw 2 ** 52;
    dw 2 ** 53;
    dw 2 ** 54;
    dw 2 ** 55;
    dw 2 ** 56;
    dw 2 ** 57;
    dw 2 ** 58;
    dw 2 ** 59;
    dw 2 ** 60;
    dw 2 ** 61;
    dw 2 ** 62;
    dw 2 ** 63;
    dw 2 ** 64;
    dw 2 ** 65;
    dw 2 ** 66;
    dw 2 ** 67;
    dw 2 ** 68;
    dw 2 ** 69;
    dw 2 ** 70;
    dw 2 ** 71;
    dw 2 ** 72;
    dw 2 ** 73;
    dw 2 ** 74;
    dw 2 ** 75;
    dw 2 ** 76;
    dw 2 ** 77;
    dw 2 ** 78;
    dw 2 ** 79;
    dw 2 ** 80;
    dw 2 ** 81;
    dw 2 ** 82;
    dw 2 ** 83;
    dw 2 ** 84;
    dw 2 ** 85;
    dw 2 ** 86;
    dw 2 ** 87;
    dw 2 ** 88;
    dw 2 ** 89;
    dw 2 ** 90;
    dw 2 ** 91;
    dw 2 ** 92;
    dw 2 ** 93;
    dw 2 ** 94;
    dw 2 ** 95;
    dw 2 ** 96;
    dw 2 ** 97;
    dw 2 ** 98;
    dw 2 ** 99;
    dw 2 ** 100;
    dw 2 ** 101;
    dw 2 ** 102;
    dw 2 ** 103;
    dw 2 ** 104;
    dw 2 ** 105;
    dw 2 ** 106;
    dw 2 ** 107;
    dw 2 ** 108;
    dw 2 ** 109;
    dw 2 ** 110;
    dw 2 ** 111;
    dw 2 ** 112;
    dw 2 ** 113;
    dw 2 ** 114;
    dw 2 ** 115;
    dw 2 ** 116;
    dw 2 ** 117;
    dw 2 ** 118;
    dw 2 ** 119;
    dw 2 ** 120;
    dw 2 ** 121;
    dw 2 ** 122;
    dw 2 ** 123;
    dw 2 ** 124;
    dw 2 ** 125;
    dw 2 ** 126;
    dw 2 ** 127;
    dw 2 ** 128;
    dw 2 ** 129;
    dw 2 ** 130;
    dw 2 ** 131;
    dw 2 ** 132;
    dw 2 ** 133;
    dw 2 ** 134;
    dw 2 ** 135;
    dw 2 ** 136;
    dw 2 ** 137;
    dw 2 ** 138;
    dw 2 ** 139;
    dw 2 ** 140;
    dw 2 ** 141;
    dw 2 ** 142;
    dw 2 ** 143;
    dw 2 ** 144;
    dw 2 ** 145;
    dw 2 ** 146;
    dw 2 ** 147;
    dw 2 ** 148;
    dw 2 ** 149;
    dw 2 ** 150;
    dw 2 ** 151;
    dw 2 ** 152;
    dw 2 ** 153;
    dw 2 ** 154;
    dw 2 ** 155;
    dw 2 ** 156;
    dw 2 ** 157;
    dw 2 ** 158;
    dw 2 ** 159;
    dw 2 ** 160;
    dw 2 ** 161;
    dw 2 ** 162;
    dw 2 ** 163;
    dw 2 ** 164;
    dw 2 ** 165;
    dw 2 ** 166;
    dw 2 ** 167;
    dw 2 ** 168;
    dw 2 ** 169;
    dw 2 ** 170;
    dw 2 ** 171;
    dw 2 ** 172;
    dw 2 ** 173;
    dw 2 ** 174;
    dw 2 ** 175;
    dw 2 ** 176;
    dw 2 ** 177;
    dw 2 ** 178;
    dw 2 ** 179;
    dw 2 ** 180;
    dw 2 ** 181;
    dw 2 ** 182;
    dw 2 ** 183;
    dw 2 ** 184;
    dw 2 ** 185;
    dw 2 ** 186;
    dw 2 ** 187;
    dw 2 ** 188;
    dw 2 ** 189;
    dw 2 ** 190;
    dw 2 ** 191;
    dw 2 ** 192;
    dw 2 ** 193;
    dw 2 ** 194;
    dw 2 ** 195;
    dw 2 ** 196;
    dw 2 ** 197;
    dw 2 ** 198;
    dw 2 ** 199;
    dw 2 ** 200;
    dw 2 ** 201;
    dw 2 ** 202;
    dw 2 ** 203;
    dw 2 ** 204;
    dw 2 ** 205;
    dw 2 ** 206;
    dw 2 ** 207;
    dw 2 ** 208;
    dw 2 ** 209;
    dw 2 ** 210;
    dw 2 ** 211;
    dw 2 ** 212;
    dw 2 ** 213;
    dw 2 ** 214;
    dw 2 ** 215;
    dw 2 ** 216;
    dw 2 ** 217;
    dw 2 ** 218;
    dw 2 ** 219;
    dw 2 ** 220;
    dw 2 ** 221;
    dw 2 ** 222;
    dw 2 ** 223;
    dw 2 ** 224;
    dw 2 ** 225;
    dw 2 ** 226;
    dw 2 ** 227;
    dw 2 ** 228;
    dw 2 ** 229;
    dw 2 ** 230;
    dw 2 ** 231;
    dw 2 ** 232;
    dw 2 ** 233;
    dw 2 ** 234;
    dw 2 ** 235;
    dw 2 ** 236;
    dw 2 ** 237;
    dw 2 ** 238;
    dw 2 ** 239;
    dw 2 ** 240;
    dw 2 ** 241;
    dw 2 ** 242;
    dw 2 ** 243;
    dw 2 ** 244;
    dw 2 ** 245;
    dw 2 ** 246;
    dw 2 ** 247;
    dw 2 ** 248;
    dw 2 ** 249;
    dw 2 ** 250;
    dw 2 ** 251;
}

// @notice Assert that a is less than or equal to b.
// @dev Uint256 are supposed to be well formed
func assert_uint256_le{range_check_ptr}(a: Uint256, b: Uint256) {
    assert [range_check_ptr + 0] = b.high - a.high;
    if (b.high != a.high) {
        let range_check_ptr = range_check_ptr + 1;
        return ();
    }
    assert [range_check_ptr + 1] = b.low - a.low;
    let range_check_ptr = range_check_ptr + 2;
    return ();
}

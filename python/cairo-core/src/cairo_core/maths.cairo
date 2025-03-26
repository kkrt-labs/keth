from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.math import assert_le_felt, assert_le
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.common.uint256 import Uint256
from cairo_core.comparison import is_zero

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
    %{ is_positive_hint %}
    if (is_positive != 0) {
        assert_le_felt(value, STARK_DIV_2_MIN_ONE);
        return 1;
    } else {
        assert_le_felt(STARK_DIV_2_PLUS_ONE, value);
        return -1;
    }
}

@known_ap_change
func pow2(i: felt) -> felt {
    let (data_address) = get_label_location(data);
    return [data_address + i];

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

// @notice Returns 256^i for i in [0, 31]
func pow256(i: felt) -> felt {
    let (data_address) = get_label_location(data);
    return [data_address + i];

    data:
    dw 256 ** 0;
    dw 256 ** 1;
    dw 256 ** 2;
    dw 256 ** 3;
    dw 256 ** 4;
    dw 256 ** 5;
    dw 256 ** 6;
    dw 256 ** 7;
    dw 256 ** 8;
    dw 256 ** 9;
    dw 256 ** 10;
    dw 256 ** 11;
    dw 256 ** 12;
    dw 256 ** 13;
    dw 256 ** 14;
    dw 256 ** 15;
    dw 256 ** 16;
    dw 256 ** 17;
    dw 256 ** 18;
    dw 256 ** 19;
    dw 256 ** 20;
    dw 256 ** 21;
    dw 256 ** 22;
    dw 256 ** 23;
    dw 256 ** 24;
    dw 256 ** 25;
    dw 256 ** 26;
    dw 256 ** 27;
    dw 256 ** 28;
    dw 256 ** 29;
    dw 256 ** 30;
    dw 256 ** 31;
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

// @notice Splits a felt252 into `len` bytes, little-endian, and outputs to `dst`.
// @dev Can only split up to 31 bytes included.
// @dev Panics if the length is 0.
func felt252_to_bytes_le{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    value: felt, len: felt, dst: felt*
) {
    if (len == 0) {
        return ();
    }
    with_attr error_message("felt252_to_bytes_le: len must be < 32") {
        assert [range_check_ptr] = len;
        assert [range_check_ptr + 1] = 31 - len;
        let range_check_ptr = range_check_ptr + 2;
    }
    let output = &dst[0];
    %{ felt252_to_bytes_le %}

    tempvar range_check_ptr = range_check_ptr;
    tempvar idx = 0;
    tempvar acc = 0;

    loop:
    let range_check_ptr = [ap - 3];
    let idx = [ap - 2];
    let acc = [ap - 1];
    let is_done = is_zero(len - idx);

    static_assert idx == [ap - 6];
    static_assert acc == [ap - 5];
    jmp end if is_done != 0;

    with_attr error_message("felt252_to_bytes_le: byte not in bounds") {
        assert [range_check_ptr] = output[idx];
        assert [range_check_ptr + 1] = 255 - output[idx];
    }
    let pow256_idx = pow256(idx);
    tempvar current_value = output[idx] * pow256_idx;

    tempvar range_check_ptr = range_check_ptr + 2;
    tempvar idx = idx + 1;
    tempvar acc = acc + current_value;
    jmp loop;

    end:
    let idx = [ap - 6];
    let acc = [ap - 5];

    if (idx == 31) {
        with_attr error_message("felt252_to_bytes_le: bad output") {
            assert acc = value;
        }
        return ();
    }

    // Case not full length of a felt: apply a mask on the value to verify
    tempvar mask = pow256(idx) - 1;
    assert bitwise_ptr.x = value;
    assert bitwise_ptr.y = mask;
    tempvar value_masked = bitwise_ptr.x_and_y;
    let bitwise_ptr = bitwise_ptr + BitwiseBuiltin.SIZE;

    with_attr error_message("felt252_to_bytes_le: bad output") {
        assert acc = value_masked;
    }

    return ();
}

// @notice Splits a felt252 into `len` bytes, big-endian, and outputs to `dst`.
// @dev Can only split up to 31 bytes included.
// @dev Panics if the length is 0.
func felt252_to_bytes_be{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    value: felt, len: felt, dst: felt*
) {
    alloc_locals;
    if (len == 0) {
        return ();
    }
    with_attr error_message("felt252_to_bytes_be: len must be < 32") {
        assert [range_check_ptr] = len;
        assert [range_check_ptr + 1] = 31 - len;
        let range_check_ptr = range_check_ptr + 2;
    }
    let output = &dst[0];
    %{ felt252_to_bytes_be %}

    tempvar range_check_ptr = range_check_ptr;
    tempvar idx = 0;
    tempvar acc = 0;

    loop:
    let range_check_ptr = [ap - 3];
    let idx = [ap - 2];
    let acc = [ap - 1];
    let is_done = is_zero(len - idx);

    static_assert idx == [ap - 6];
    static_assert acc == [ap - 5];
    jmp end if is_done != 0;

    with_attr error_message("felt252_to_bytes_be: byte not in bounds") {
        assert [range_check_ptr] = output[idx];
        assert [range_check_ptr + 1] = 255 - output[idx];
    }
    let pow256_idx = pow256(len - 1 - idx);
    tempvar current_value = output[idx] * pow256_idx;

    tempvar range_check_ptr = range_check_ptr + 2;
    tempvar idx = idx + 1;
    tempvar acc = acc + current_value;
    jmp loop;

    end:
    let idx = [ap - 6];
    let acc = [ap - 5];

    if (idx == 31) {
        with_attr error_message("felt252_to_bytes_be: bad output") {
            assert acc = value;
        }
        return ();
    }

    // Case not full length of a felt: apply a mask on the value to verify
    tempvar mask = pow256(idx) - 1;
    assert bitwise_ptr.x = value;
    assert bitwise_ptr.y = mask;
    tempvar value_masked = bitwise_ptr.x_and_y;
    let bitwise_ptr = bitwise_ptr + BitwiseBuiltin.SIZE;

    with_attr error_message("felt252_to_bytes_be: bad output") {
        assert acc = value_masked;
    }

    return ();
}

func felt252_bit_length{range_check_ptr}(value: felt) -> felt {
    alloc_locals;

    if (value == 0) {
        return 0;
    }

    tempvar bit_length;
    %{ bit_length_hint %}

    assert_le(bit_length, 252);
    let lower_bound = pow2(bit_length - 1);
    assert_le_felt(lower_bound, value);
    if (bit_length == 252) {
        return bit_length;
    }
    let upper_bound = pow2(bit_length);
    assert_le_felt(value + 1, upper_bound);

    return bit_length;
}

func felt252_to_bits{range_check_ptr}(limb: felt, bits_ptr: felt*, current_len: felt) -> felt {
    alloc_locals;
    if (limb == 0) {
        return current_len;
    }
    with_attr error_message("felt252_to_bits: limb must be < 252") {
        assert [range_check_ptr] = limb;
        assert [range_check_ptr + 1] = 251 - limb;
        let range_check_ptr = range_check_ptr + 2;
    }

    let output = &bits_ptr[0];
    %{ felt252_to_bits %}

    tempvar range_check_ptr = range_check_ptr;
    tempvar current_len = current_len;
    tempvar i = 0;
    tempvar acc = 0;

    loop:
    let range_check_ptr = [ap - 3];
    let current_len = [ap - 2];
    let limb = [ap - 1];

    let is_done = is_zero(limb);
    jmp end if is_done != 0;

    // Get the current bit using modulo 2
    let (_, bit) = unsigned_div_rem(limb, 2);
    assert bits_ptr[current_len] = bit;
    
    // all the generated felt elements should be either 0 or 1
    let bit_minus_one = bit - 1;
    let product = bit * bit_minus_one;
    let is_valid_bit = is_zero(product);
    
    with_attr error_message("felt252_to_bits: bits must be 0 or 1") {
        assert is_valid_bit = 1;
    }
    
    // Compute the next limb value
    let (limb, _) = unsigned_div_rem(limb, 2);
    tempvar current_len = current_len + 1;
    tempvar i = i + 1;
    tempvar acc = acc + bit * pow2(i);
    jmp loop;

    end:
    with_attr error_message("felt252_to_bits: bad output") {
        assert acc = limb;
    }
    return current_len;
}

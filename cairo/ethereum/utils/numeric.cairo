from starkware.cairo.common.math_cmp import is_le, is_not_zero
from starkware.cairo.common.uint256 import uint256_reverse_endian
from ethereum_types.numeric import Uint, U256, U256Struct, bool
from ethereum_types.bytes import Bytes32, Bytes32Struct, Bytes20, Bytes
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

from starkware.cairo.common.math import split_felt
from starkware.cairo.common.uint256 import word_reverse_endian, Uint256, uint256_le, uint256_mul
from src.utils.uint256 import uint256_add, uint256_sub
from src.utils.utils import Helpers
from src.utils.bytes import bytes_to_felt

func min{range_check_ptr}(a: felt, b: felt) -> felt {
    alloc_locals;

    tempvar is_min_b;
    %{ b_le_a %}
    jmp min_is_b if is_min_b != 0;

    min_is_a:
    assert [range_check_ptr] = b - a;
    let range_check_ptr = range_check_ptr + 1;
    return a;

    min_is_b:
    assert [range_check_ptr] = a - b;
    let range_check_ptr = range_check_ptr + 1;
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

func U256_from_be_bytes{bitwise_ptr: BitwiseBuiltin*}(bytes: Bytes32) -> U256 {
    // All bytes in the repository are expected to be in little endian so we need to reverse them
    let (value) = uint256_reverse_endian([bytes.value]);
    tempvar res = U256(new U256Struct(value.low, value.high));
    return res;
}

func U256_from_le_bytes(bytes: Bytes32) -> U256 {
    tempvar res = U256(bytes.value);
    return res;
}

func U256_to_be_bytes{bitwise_ptr: BitwiseBuiltin*}(value: U256) -> Bytes32 {
    let (reversed_value) = uint256_reverse_endian([value.value]);
    tempvar res = Bytes32(new Bytes32Struct(reversed_value.low, reversed_value.high));
    return res;
}

func U256_to_le_bytes(value: U256) -> Bytes32 {
    tempvar res = Bytes32(value.value);
    return res;
}

func U256__eq__(a: U256, b: U256) -> bool {
    if (a.value.low == b.value.low and a.value.high == b.value.high) {
        tempvar res = bool(1);
        return res;
    }
    tempvar res = bool(0);
    return res;
}

func U256_from_be_bytes20{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(bytes20: Bytes20) -> U256 {
    // 1. Splits the 20-byte value into high and low parts
    let (bytes20_high, bytes20_low) = split_felt(bytes20.value);
    // 2. Reverses the endianness of both parts
    let (rev_low) = word_reverse_endian(bytes20_low);
    let (rev_high) = word_reverse_endian(bytes20_high);
    // 3. The final value contains 16bytes in the low part and 4 bytes in the high part
    let (high, remainder) = divmod(rev_low, 2 ** 96);
    let (low_low, _) = divmod(rev_high, 2 ** 96);
    let low = low_low + remainder * 2 ** 32;
    tempvar res = U256(new U256Struct(low=low, high=high));
    return res;
}

func U256_to_le_bytes20{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(value: U256) -> Bytes20 {
    let high = value.value.high;
    let is_within_bounds = is_le(high, 2 ** 32 - 1);
    with_attr error_message("OverflowError") {
        assert is_within_bounds = 1;
    }
    let (high_reversed) = word_reverse_endian(high);
    let (low_reversed) = word_reverse_endian(value.value.low);
    let (high_reversed_shifted, _) = divmod(high_reversed, 2 ** 96);
    let res_felt = high_reversed_shifted + low_reversed * 2 ** 32;
    tempvar res = Bytes20(res_felt);
    return res;
}

func U256_from_felt{range_check_ptr}(value: felt) -> U256 {
    let (high, low) = split_felt(value);
    tempvar res = U256(new U256Struct(low, high));
    return res;
}

// @dev Panics if overflow
func U256_add{range_check_ptr}(a: U256, b: U256) -> U256 {
    alloc_locals;
    let (res, carry) = uint256_add([a.value], [b.value]);

    with_attr error_message("OverflowError") {
        assert carry = 0;
    }

    tempvar result = U256(new U256Struct(res.low, res.high));
    return result;
}

// @dev Panics if underflow with OverflowError
func U256_sub{range_check_ptr}(a: U256, b: U256) -> U256 {
    alloc_locals;
    let is_within_bounds = U256_le(b, a);
    with_attr error_message("OverflowError") {
        assert is_within_bounds.value = 1;
    }
    let (result) = uint256_sub([a.value], [b.value]);
    tempvar res = U256(new U256Struct(result.low, result.high));
    return res;
}

func U256_le{range_check_ptr}(a: U256, b: U256) -> bool {
    let (result) = uint256_le([a.value], [b.value]);
    tempvar res = bool(result);
    return res;
}

func U256_mul{range_check_ptr}(a: U256, b: U256) -> U256 {
    alloc_locals;
    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let (local low, high) = uint256_mul([a.value], [b.value]);

    with_attr error_message("OverflowError") {
        assert high.high = 0;
        assert high.low = 0;
    }
    tempvar result = U256(&low);
    return result;
}

func Uint_from_be_bytes{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(bytes: Bytes) -> Uint {
    with_attr error_message("OverflowError") {
        assert [range_check_ptr] = 8 - bytes.value.len;
        let range_check_ptr = range_check_ptr + 1;
    }
    let value = bytes_to_felt(bytes.value.len, bytes.value.data);
    tempvar res = Uint(value);
    return res;
}

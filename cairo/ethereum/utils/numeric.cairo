from starkware.cairo.common.math_cmp import is_le, is_not_zero, is_le_felt
from starkware.cairo.common.math import safe_mult
from starkware.cairo.common.uint256 import uint256_reverse_endian
from ethereum_types.numeric import Uint, U256, U256Struct, bool, U64
from ethereum_types.bytes import Bytes32, Bytes32Struct, Bytes20, Bytes
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.math import assert_le_felt

from starkware.cairo.common.math import split_felt
from starkware.cairo.common.uint256 import word_reverse_endian, Uint256, uint256_le, uint256_mul
from legacy.utils.uint256 import uint256_add, uint256_sub
from legacy.utils.utils import Helpers
from legacy.utils.bytes import bytes_to_felt, uint256_from_bytes_be

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

// @dev: Saturates when the numerator_accumulated * numerator is greater than 2**128 - 1
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

    let saturate = is_le_felt(2 ** 128, value);
    if (saturate != 0) {
        // Return current accumulated output/denominator when we hit saturation
        let (res, _) = divmod(output, denominator);
        return res;
    }

    let (numerator_accumulated, _) = divmod(value, div);
    let i = i + 1;

    return _taylor_exponential(output, i, numerator_accumulated, numerator, denominator);
}

func U256_from_be_bytes32{bitwise_ptr: BitwiseBuiltin*}(bytes: Bytes32) -> U256 {
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

// / Converts a 20-byte big-endian value into a U256 in little-endian representation.
// / If the input is a 20-byte value in little-endian, then the output will be a U256 in big-endian.
// / The algorithm works in steps:
// / 1. Split the 20-byte value into high and low parts:
// /    [b0, b1, ..., b19] -> high=[b0,...,b3], low=[b4,...,b19]
// /
// / 2. Reverse endianness of both parts using word_reverse_endian:
// /    high: [b0,b1,b2,b3] -> [b3,b2,b1,b0]
// /    low:  [b4,...,b19] -> [b19,...,b4]
// /
// / 3. Construct final U256 value:
// /    - high field: first 4 bytes [b3,b2,b1,b0]
// /    - low field: remaining 16 bytes [b19,...,b4]
// /
// / Example for input 0x0102...1314:
// / Initial:     [01,02,...,13,14]
// / Split:       high=[01,02,03,04], low=[05,...,13,14]
// / Reversed:    high=[04,03,02,01], low=[14,13,...,05]
// / Final U256:  high=0x04030201, low=0x14130C0B...0605
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

// / Converts a U256 in little-endian representation to a 20-byte value in big-endian format.
// / If the input is a U256 in big-endian, then the output will be a 20-byte value in little-endian.
// / The algorithm works in steps:
// / 1. Verify the high field fits in 4 bytes (must be <= 2^32 - 1)
// /
// / 2. Reverse endianness of both fields:
// /    high: [b3,b2,b1,b0] -> [b0,b1,b2,b3]
// /    low:  [b19,...,b4] -> [b4,...,b19]
// /
// / 3. Combine into 20-byte big-endian result:
// /    [b0,b1,b2,b3,b4,...,b19]
// /
// / Example for input U256{high: 0x04030201, low: 0x14130C0B...0605}:
// / Initial:     high=[04,03,02,01], low=[14,13,...,05]
// / Reversed:    high=[01,02,03,04], low=[05,...,13,14]
// / Combined:    [01,02,...,13,14]
// /
// / Panics with "OverflowError" if high field > 2^32 - 1
func U256_to_be_bytes20{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(value: U256) -> Bytes20 {
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

func U256_from_Uint{range_check_ptr}(value: Uint) -> U256 {
    let (high, low) = split_felt(value.value);
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

func U256_add_with_carry{range_check_ptr}(a: U256, b: U256) -> (U256, felt) {
    alloc_locals;
    let (res, carry) = uint256_add([a.value], [b.value]);
    tempvar result = U256(new U256Struct(res.low, res.high));
    return (result, carry);
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

// Returns the minimum of two U256 values
func U256_min{range_check_ptr}(a: U256, b: U256) -> U256 {
    let is_b_le = U256_le(b, a);
    if (is_b_le.value == 1) {
        return b;
    }
    return a;
}

func U64_from_be_bytes{range_check_ptr}(bytes: Bytes) -> U64 {
    with_attr error_message("ValueError") {
        assert [range_check_ptr] = 8 - bytes.value.len;
        let range_check_ptr = range_check_ptr + 1;
    }
    let value = bytes_to_felt(bytes.value.len, bytes.value.data);
    let res = U64(value);
    return res;
}

// @dev Panics if len(bytes) > 31
// @dev Note Uint type from EELS is unbounded.
func Uint_from_be_bytes{range_check_ptr}(bytes: Bytes) -> Uint {
    with_attr error_message("ValueError") {
        assert [range_check_ptr] = 31 - bytes.value.len;
        let range_check_ptr = range_check_ptr + 1;
    }
    let value = bytes_to_felt(bytes.value.len, bytes.value.data);
    tempvar res = Uint(value);
    return res;
}

func U256_to_Uint{range_check_ptr}(value: U256) -> Uint {
    with_attr error_message("ValueError") {
        // 0x8000000000000110000000000000000 is the high 128 bits of DEFAULT_PRIME
        assert_le_felt(value.value.high, 0x8000000000000110000000000000000);
        assert [range_check_ptr] = value.value.low;
        let range_check_ptr = range_check_ptr + 1;
    }
    let res = Uint(value.value.low + value.value.high * 2 ** 128);
    return res;
}

func U256_from_be_bytes{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(bytes: Bytes) -> U256 {
    let res = uint256_from_bytes_be(bytes.value.len, bytes.value.data);
    tempvar res_u256 = U256(new U256Struct(res.low, res.high));
    return res_u256;
}

func Bytes32_from_be_bytes{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(bytes: Bytes) -> Bytes32 {
    let res = uint256_from_bytes_be(bytes.value.len, bytes.value.data);
    let (res_reversed) = uint256_reverse_endian(res);
    tempvar res_bytes32 = Bytes32(new Bytes32Struct(res_reversed.low, res_reversed.high));
    return res_bytes32;
}

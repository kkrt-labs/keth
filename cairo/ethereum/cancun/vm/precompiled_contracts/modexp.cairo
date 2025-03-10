from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    KeccakBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
    UInt384,
)
from starkware.cairo.common.memset import memset
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import uint256_mul, uint256_eq, uint256_le
from starkware.cairo.common.uint256 import uint256_to_felt, Uint256
from starkware.cairo.common.math_cmp import is_le, is_le_felt, is_not_zero
from cairo_core.comparison import is_zero
from ethereum_types.bytes import Bytes, BytesStruct
from ethereum_types.numeric import U256, U256Struct, Uint, U384
from ethereum.utils.numeric import (
    divmod,
    U384_is_zero,
    U384_is_one,
    U256_from_be_bytes,
    Uint_from_be_bytes,
    U256__eq__,
    U256_add,
    U256_le,
    U256_add_with_carry,
    U256_min,
    U256_max,
    U256_to_Uint,
    Uint_bit_length,
    U384_from_be_bytes,
    U384_to_be_bytes,
    U384__eq__,
    max,
    min,
)
from ethereum.cancun.vm.evm_impl import Evm, EvmImpl
from ethereum.cancun.vm.gas import charge_gas
from ethereum.cancun.vm.memory import buffer_read
from ethereum.exceptions import EthereumException
from cairo_core.control_flow import raise
from cairo_ec.circuits.mod_ops_compiled import mul
from legacy.utils.bytes import felt_to_bytes
from legacy.utils.uint256 import uint256_unsigned_div_rem
from starkware.cairo.common.memcpy import memcpy

from ethereum.cancun.vm.exceptions import OutOfGasError

const GQUADDIVISOR = 3;
const MAX_EXPONENT_LENGTH = 31;

// Diverge from the specs:
// The max length for exponent is 31 bytes, hence exp_head will be 31 bytes at most
// The max length for modulus and base is 48 bytes
func modexp{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;

    let data = evm.value.message.value.data;
    tempvar u256_zero = U256(new U256Struct(0, 0));
    tempvar u256_max_exponent_length = U256(new U256Struct(MAX_EXPONENT_LENGTH, 0));
    tempvar u256_thirty_two = U256(new U256Struct(32, 0));
    tempvar u256_sixty_four = U256(new U256Struct(64, 0));
    tempvar u256_ninety_six = U256(new U256Struct(96, 0));
    tempvar u256_forty_eight = U256(new U256Struct(48, 0));

    let res = buffer_read(data, u256_zero, u256_thirty_two);
    let base_length = U256_from_be_bytes(res);
    let base_length_too_big = U256_le(u256_forty_eight, base_length);
    if (base_length_too_big.value != 0) {
        raise('InputError');
    }

    let res = buffer_read(data, u256_thirty_two, u256_thirty_two);
    let exp_length = U256_from_be_bytes(res);
    let exp_length_too_big = U256_le(u256_max_exponent_length, exp_length);
    if (exp_length_too_big.value != 0) {
        raise('InputError');
    }

    let res = buffer_read(data, u256_sixty_four, u256_thirty_two);
    let modulus_length = U256_from_be_bytes(res);
    let modulus_length_too_big = U256_le(u256_forty_eight, modulus_length);
    if (modulus_length_too_big.value != 0) {
        raise('InputError');
    }

    let exp_start = U256_add(u256_ninety_six, base_length);

    // Diverge from the specs: forcing to read max 31 bytes for exponent head
    let min_len = U256_min(u256_max_exponent_length, exp_length);
    let res = buffer_read(data, exp_start, min_len);
    let exp_head = Uint_from_be_bytes(res);

    let gas = gas_cost(base_length, modulus_length, exp_length, exp_head);

    let err = charge_gas(gas);
    if (cast(err, felt) != 0) {
        return err;
    }

    let base_zero = U256__eq__(base_length, u256_zero);
    let modulus_zero = U256__eq__(modulus_length, u256_zero);
    if (base_zero.value != 0 and modulus_zero.value != 0) {
        tempvar empty_bytes = Bytes(new BytesStruct(cast(0, felt*), 0));
        EvmImpl.set_output(empty_bytes);
        tempvar ok = cast(0, EthereumException*);
        return ok;
    }

    let base = buffer_read(data, u256_ninety_six, base_length);
    let exp = buffer_read(data, exp_start, exp_length);
    let modulus_start = U256_add(exp_start, exp_length);
    let modulus = buffer_read(data, modulus_start, modulus_length);

    let base_u384 = U384_from_be_bytes(base);
    let exp_u384 = U384_from_be_bytes(exp);
    let modulus_u384 = U384_from_be_bytes(modulus);
    tempvar u384_zero = U384(new UInt384(0, 0, 0, 0));

    let modulus_is_zero = U384__eq__(modulus_u384, u384_zero);
    if (modulus_is_zero.value != 0) {
        let (zeros_ptr) = alloc();
        let zeros_len = uint256_to_felt([modulus_length.value]);
        memset(zeros_ptr, 0, zeros_len);
        tempvar result = Bytes(new BytesStruct(zeros_ptr, zeros_len));
        EvmImpl.set_output(result);
        tempvar ok = cast(0, EthereumException*);
        return ok;
    }

    // Square-and-multiply algorithm for modular exponentiation
    let result_uint384 = mod_pow(base_u384, exp_u384, modulus_u384);

    let result_bytes_len = uint256_to_felt([modulus_length.value]);
    let result = U384_to_be_bytes(result_uint384, result_bytes_len);

    EvmImpl.set_output(result);
    tempvar ok = cast(0, EthereumException*);
    return ok;
}

func mod_pow{
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(base: U384, exponent: U384, modulus: U384) -> U384 {
    alloc_locals;

    let modulus_is_zero = U384_is_zero(modulus);
    if (modulus_is_zero != 0) {
        tempvar result = U384(new UInt384(0, 0, 0, 0));
        return result;
    }

    let modulus_is_one = U384_is_one(modulus);
    if (modulus_is_one != 0) {
        tempvar result = U384(new UInt384(0, 0, 0, 0));
        return result;
    }

    let exponent_is_zero = U384_is_zero(exponent);
    if (exponent_is_zero != 0) {
        tempvar result = U384(new UInt384(1, 0, 0, 0));
        return result;
    }

    let base_is_zero = U384_is_zero(base);
    if (base_is_zero != 0) {
        tempvar result = U384(new UInt384(0, 0, 0, 0));
        return result;
    }

    let (bits_ptr, bits_len) = get_u384_bits_little(exponent);
    tempvar res = U384(new UInt384(1, 0, 0, 0));

    return mod_pow_recursive(base, bits_ptr, bits_len, 0, res, modulus);
}

func mod_pow_recursive{
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(
    base: U384, bits_ptr: felt*, bits_len: felt, current_bit: felt, result: U384, modulus: U384
) -> U384 {
    alloc_locals;

    // Base case: if we've processed all bits, return the result
    if (current_bit == bits_len) {
        return result;
    }

    // Get current bit value
    let bit_value = bits_ptr[current_bit];

    // Calculate new result and new base for this iteration
    let (new_result, new_base) = mod_exp_loop_inner(modulus, bit_value, base, result);

    // Continue with next bit
    return mod_pow_recursive(new_base, bits_ptr, bits_len, current_bit + 1, new_result, modulus);
}

func mod_exp_loop_inner{
    range_check_ptr, range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(modulus: U384, bit: felt, base: U384, res: U384) -> (U384, U384) {
    alloc_locals;

    if (bit == 0) {
        // Bit not set, keep result unchanged
        tempvar new_res = res;
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
    } else {
        // Bit is set, multiply by base
        let res_with_base_ptr = mul(res.value, base.value, modulus.value);
        tempvar new_res = U384(res_with_base_ptr);
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
    }

    tempvar range_check96_ptr = range_check96_ptr;
    tempvar add_mod_ptr = add_mod_ptr;
    tempvar mul_mod_ptr = mul_mod_ptr;

    // Square the base for next iteration
    let base_squared_ptr = mul(base.value, base.value, modulus.value);
    let new_base = U384(base_squared_ptr);

    return (new_res, new_base);
}

func get_u384_bits_little{range_check_ptr}(num: U384) -> (felt*, felt) {
    alloc_locals;
    let (bits_ptr) = alloc();
    // Process limb0 (d0)
    let bits_len = extract_limb_bits(num.value.d0, bits_ptr, 0);
    // Process limb1 (d1)
    let limb1_not_zero = is_not_zero(num.value.d1);
    if (limb1_not_zero != 0) {
        // Use memset to pad with zeros until we reach 96 bits if needed
        let bits_len_padded = 96;
        memset(bits_ptr + bits_len, 0, bits_len_padded - bits_len);
        let bits_len_updated = extract_limb_bits(num.value.d1, bits_ptr, bits_len_padded);
        tempvar bits_ptr = bits_ptr;
        tempvar bits_len = bits_len_updated;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar bits_ptr = bits_ptr;
        tempvar bits_len = bits_len;
        tempvar range_check_ptr = range_check_ptr;
    }
    // Process limb2 (d2)
    let limb2_not_zero = is_not_zero(num.value.d2);
    tempvar bits_ptr = bits_ptr;
    tempvar range_check_ptr = range_check_ptr;
    if (limb2_not_zero != 0) {
        // Use memset to pad with zeros until we reach 192 bits if needed
        let bits_len_padded = 192;
        memset(bits_ptr + bits_len, 0, bits_len_padded - bits_len);
        let bits_len_updated = extract_limb_bits(num.value.d2, bits_ptr, bits_len_padded);
        tempvar bits_ptr = bits_ptr;
        tempvar bits_len = bits_len_updated;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar bits_ptr = bits_ptr;
        tempvar bits_len = bits_len;
        tempvar range_check_ptr = range_check_ptr;
    }
    // Process limb3 (d3)
    let limb3_not_zero = is_not_zero(num.value.d3);
    tempvar bits_ptr = bits_ptr;
    tempvar range_check_ptr = range_check_ptr;
    if (limb3_not_zero != 0) {
        // Use memset to pad with zeros until we reach 288 bits if needed
        let bits_len_padded = 288;
        memset(bits_ptr + bits_len, 0, bits_len_padded - bits_len);
        let bits_len_updated = extract_limb_bits(num.value.d3, bits_ptr, bits_len_padded);
        return (bits_ptr, bits_len_updated);
    } else {
        return (bits_ptr, bits_len);
    }
}

func extract_limb_bits{range_check_ptr}(limb: felt, bits_ptr: felt*, current_len: felt) -> felt {
    // Check if limb is zero
    let is_limb_zero = is_zero(limb);
    if (is_limb_zero == 1) {
        return current_len;
    }

    // Extract the least significant bit
    let (q, r) = divmod(limb, 2);
    assert bits_ptr[current_len] = r;

    // Continue with the remaining bits
    return extract_limb_bits(q, bits_ptr, current_len + 1);
}

// Saturates at 2^128 - 1
// This means words ** 2 <= 2**128 -1
// words <= 2**64 - 1 hence
// (max_length + 7) // 8 <= 2**64 - 1
// max_length <= 8 * 2**64 - 15
// max_length <= 2**67 - 15
func complexity{range_check_ptr}(base_length: U256, modulus_length: U256) -> Uint {
    alloc_locals;

    let max_len = U256_max(base_length, modulus_length);
    tempvar seven_u256 = U256(new U256Struct(7, 0));
    let (words, overflow) = U256_add_with_carry(max_len, seven_u256);

    tempvar max_length = new Uint256(2 ** 67 - 14, 0);
    let (words_too_big) = uint256_le([max_length], [words.value]);
    if (overflow + words_too_big != 0) {
        let result = Uint(2 ** 128 - 1);
        return result;
    }

    tempvar eight_u256 = U256(new U256Struct(8, 0));
    let (quotient, _) = uint256_unsigned_div_rem([words.value], [eight_u256.value]);
    let (res, _) = uint256_mul(quotient, quotient);

    let res_felt = uint256_to_felt(res);
    let res_uint = Uint(res_felt);
    return res_uint;
}

// Diverge from the specs: exponent_head is limited to 31 bytes
func iterations{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    exponent_length: U256, exponent_head: Uint
) -> Uint {
    alloc_locals;

    let exp_len_uint = uint256_to_felt([exponent_length.value]);

    let is_exp_len_le_31 = is_le(exp_len_uint, MAX_EXPONENT_LENGTH);
    let is_exp_len_zero = is_zero(exponent_head.value);

    if (is_exp_len_le_31 != 0 and is_exp_len_zero != 0) {
        let one = Uint(1);
        return one;
    }
    if (is_exp_len_le_31 != 0) {
        let bit_length = Uint_bit_length(exponent_head);

        let is_bit_length_zero = is_zero(bit_length);
        if (is_bit_length_zero != 0) {
            let one = Uint(1);
            return one;
        }
        let count = bit_length - 1;
        let res = max(count, 1);
        let result = Uint(res);
        return result;
    }
    raise('InputError');
    let zero = Uint(0);
    return zero;
}

// Saturated gas cost at 2^128 - 1
// Assume the exponent is 31 bytes at most
func gas_cost{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    base_length: U256, modulus_length: U256, exponent_length: U256, exponent_head: Uint
) -> Uint {
    alloc_locals;

    let complex = complexity(base_length, modulus_length);
    let iters = iterations(exponent_length, exponent_head);

    let complex_too_big = is_le_felt(2 ** 128, complex.value);
    if (complex_too_big != 0) {
        let saturated_gas = Uint(2 ** 128 - 1);
        return saturated_gas;
    }
    tempvar cost = complex.value * iters.value;
    let oog = is_le_felt(2 ** 131, cost);  // 2**128 * 8
    if (oog != 0) {
        let saturated_gas = Uint(2 ** 128 - 1);
        return saturated_gas;
    }
    let (gas, _) = divmod(cost, GQUADDIVISOR);
    let gas_too_big = is_le_felt(2 ** 128, gas);
    if (gas_too_big == 1) {
        let saturated_gas = Uint(2 ** 128 - 1);
        return saturated_gas;
    }
    let gas_cost = max(gas, 200);
    let result = Uint(gas_cost);
    return result;
}

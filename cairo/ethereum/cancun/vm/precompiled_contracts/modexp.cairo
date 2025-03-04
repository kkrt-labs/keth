from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    KeccakBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
    UInt384,
)
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import uint256_to_felt
from starkware.cairo.common.math_cmp import is_le, is_le_felt, is_not_zero
from cairo_core.comparison import is_zero
from ethereum_types.bytes import Bytes, BytesStruct
from ethereum_types.numeric import U256, U256Struct, Uint, U384
from ethereum.utils.numeric import (
    divmod,
    is_U384_zero,
    is_U384_one,
    U256_from_be_bytes,
    Uint_from_be_bytes,
    U256__eq__,
    U256_add,
    U256_min,
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
from starkware.cairo.common.memcpy import memcpy

const GQUADDIVISOR = 3;

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
    tempvar u256_thirty_one = U256(new U256Struct(31, 0));
    tempvar u256_thirty_two = U256(new U256Struct(32, 0));
    tempvar u256_sixty_four = U256(new U256Struct(64, 0));
    tempvar u256_ninety_six = U256(new U256Struct(96, 0));

    let res = buffer_read(data, u256_zero, u256_thirty_two);
    let base_length = U256_from_be_bytes(res);

    let res = buffer_read(data, u256_thirty_two, u256_thirty_two);
    let exp_length = U256_from_be_bytes(res);

    let res = buffer_read(data, u256_sixty_four, u256_thirty_two);
    let modulus_length = U256_from_be_bytes(res);

    let exp_start = U256_add(u256_ninety_six, base_length);

    // Diverge from the specs: forcing to read max 31 bytes for exponent head
    let min_len = U256_min(u256_thirty_one, exp_length);
    let res = buffer_read(data, exp_start, min_len);
    let exp_head = Uint_from_be_bytes(res);

    let gas = gas_cost(base_length, modulus_length, exp_length, exp_head);

    let err = charge_gas(gas);
    if (cast(err, felt) != 0) {
        return err;
    }

    let base_zero = U256__eq__(base_length, u256_zero);
    let modulus_zero = U256__eq__(modulus_length, u256_zero);
    if (base_zero.value == 1 and modulus_zero.value == 1) {
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
    if (modulus_is_zero.value == 1) {
        let (zeros_ptr_raw) = alloc();
        let zeros_ptr = cast(zeros_ptr_raw, felt*);
        let zeros_len = uint256_to_felt([modulus_length.value]);
        tempvar result = Bytes(new BytesStruct(zeros_ptr, zeros_len));
        EvmImpl.set_output(result);
        tempvar ok = cast(0, EthereumException*);
        return ok;
    }

    // Double-and-add algorithm for modular exponentiation
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

    let modulus_is_zero = is_U384_zero(modulus);
    if (modulus_is_zero == 1) {
        tempvar result = U384(new UInt384(0, 0, 0, 0));
        return result;
    }

    let modulus_is_one = is_U384_one(modulus);
    if (modulus_is_one == 1) {
        tempvar result = U384(new UInt384(0, 0, 0, 0));
        return result;
    }

    let exponent_is_zero = is_U384_zero(exponent);
    if (exponent_is_zero == 1) {
        tempvar result = U384(new UInt384(1, 0, 0, 0));
        return result;
    }

    let base_is_zero = is_U384_zero(base);
    if (base_is_zero == 1) {
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
    let bits_len = 0;

    // Process limb0 (d0)
    let (bits_ptr_updated, bits_len_updated) = extract_limb_bits(num.value.d0, bits_ptr, bits_len);

    // Process limb1 (d1)
    let limb1_not_zero = is_not_zero(num.value.d1);
    if (limb1_not_zero != 0) {
        // Pad with zeros until we reach 96 bits if needed
        let (bits_ptr_padded, bits_len_padded) = pad_zeros(bits_ptr_updated, bits_len_updated, 96);
        let (bits_ptr_updated_1, bits_len_updated_1) = extract_limb_bits(
            num.value.d1, bits_ptr_padded, bits_len_padded
        );
        tempvar bits_ptr_after_limb1 = bits_ptr_updated_1;
        tempvar bits_len_after_limb1 = bits_len_updated_1;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar bits_ptr_after_limb1 = bits_ptr_updated;
        tempvar bits_len_after_limb1 = bits_len_updated;
        tempvar range_check_ptr = range_check_ptr;
    }

    // Process limb2 (d2)
    let limb2_not_zero = is_not_zero(num.value.d2);
    if (limb2_not_zero != 0) {
        // Pad with zeros until we reach 192 bits if needed
        let (bits_ptr_padded, bits_len_padded) = pad_zeros(
            bits_ptr_after_limb1, bits_len_after_limb1, 192
        );
        let (bits_ptr_updated_2, bits_len_updated_2) = extract_limb_bits(
            num.value.d2, bits_ptr_padded, bits_len_padded
        );
        tempvar bits_ptr_after_limb2 = bits_ptr_updated_2;
        tempvar bits_len_after_limb2 = bits_len_updated_2;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar bits_ptr_after_limb2 = bits_ptr_after_limb1;
        tempvar bits_len_after_limb2 = bits_len_after_limb1;
        tempvar range_check_ptr = range_check_ptr;
    }

    // Process limb3 (d3)
    let limb3_not_zero = is_not_zero(num.value.d3);
    if (limb3_not_zero != 0) {
        // Pad with zeros until we reach 288 bits if needed
        let (bits_ptr_padded, bits_len_padded) = pad_zeros(
            bits_ptr_after_limb2, bits_len_after_limb2, 288
        );
        let (bits_ptr_updated_3, bits_len_updated_3) = extract_limb_bits(
            num.value.d3, bits_ptr_padded, bits_len_padded
        );
        return (bits_ptr_updated_3, bits_len_updated_3);
    } else {
        return (bits_ptr_after_limb2, bits_len_after_limb2);
    }
}

func extract_limb_bits{range_check_ptr}(limb: felt, bits_ptr: felt*, current_len: felt) -> (
    felt*, felt
) {
    // Check if limb is zero
    let is_limb_zero = is_zero(limb);
    if (is_limb_zero == 1) {
        return (bits_ptr, current_len);
    }

    // Extract the least significant bit
    let (q, r) = divmod(limb, 2);
    assert bits_ptr[current_len] = r;

    // Continue with the remaining bits
    return extract_limb_bits(q, bits_ptr, current_len + 1);
}

func pad_zeros{range_check_ptr}(bits_ptr: felt*, current_len: felt, target_len: felt) -> (
    felt*, felt
) {
    let is_ge = is_le(target_len, current_len);
    if (is_ge == 1) {
        return (bits_ptr, current_len);
    }

    assert bits_ptr[current_len] = 0;
    return pad_zeros(bits_ptr, current_len + 1, target_len);
}

// Assumes base_length and modulus_length are less than DEFAULT_PRIME
// Saturates at 2^128 - 1
func complexity{range_check_ptr}(base_length: U256, modulus_length: U256) -> Uint {
    alloc_locals;

    let base_length_uint = U256_to_Uint(base_length);
    let modulus_length_uint = U256_to_Uint(modulus_length);
    let max_len = max(base_length_uint.value, modulus_length_uint.value);

    let words = max_len + 7;

    let (quotient, _) = divmod(words, 8);
    let overflow = is_le_felt(2 ** 128 - 1, quotient);
    if (overflow != 0) {
        let result = Uint(2 ** 128 - 1);
        return result;
    }
    let result = Uint(quotient * quotient);
    return result;
}

// Diverge from the specs: exponent_head is limited to 31 bytes
func iterations{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    exponent_length: U256, exponent_head: Uint
) -> Uint {
    alloc_locals;

    let exp_len_uint = uint256_to_felt([exponent_length.value]);

    let is_exp_len_le_32 = is_le(exp_len_uint, 32);
    let is_exp_len_zero = is_zero(exponent_head.value);

    if (is_exp_len_le_32 == 1 and is_exp_len_zero == 1) {
        let one = Uint(1);
        return one;
    }
    if (is_exp_len_le_32 == 1) {
        let bit_length = Uint_bit_length(exponent_head);

        let is_bit_length_zero = is_zero(bit_length);
        if (is_bit_length_zero == 1) {
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
    if (complex_too_big == 1) {
        let saturated_gas = Uint(2 ** 128 - 1);
        return saturated_gas;
    }
    let cost = complex.value * iters.value;
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

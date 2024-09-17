from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.uint256 import Uint256, uint256_mul, uint256_lt
from starkware.cairo.common.bitwise import bitwise_and
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.bool import FALSE

from src.utils.uint256 import (
    uint256_sub,
    uint256_add,
    uint256_unsigned_div_rem,
    uint256_mul_div_mod,
    uint256_eq,
)

// @title ModExpHelpersUint256 Functions
// @notice This file contains a selection of helper functions for modular exponentiation and gas cost calculation.
// @author @dragan2234
// @custom:namespace ModExpHelpersUint256
namespace ModExpHelpersUint256 {
    const GAS_COST_MOD_EXP = 200;

    // @title Modular exponentiation calculation
    // @author dragan2234
    // @dev Computes x ** y % p for Uint256 numbers via fast modular exponentiation algorithm.
    // Time complexity is log_2(y).
    // Loop is implemented via uint256_mod_exp_recursive_call() function.
    func uint256_mod_exp{range_check_ptr: felt}(x: Uint256, y: Uint256, p: Uint256) -> (
        remainder: Uint256
    ) {
        alloc_locals;
        let res = Uint256(low=1, high=0);
        let (r_x, r_y, r_res) = uint256_mod_exp_recursive_call(x, y, res, p);
        let (quotient, remainder) = uint256_unsigned_div_rem(r_res, p);
        return (remainder=remainder);
    }

    func uint256_mod_exp_recursive_call{range_check_ptr: felt}(
        x: Uint256, y: Uint256, res: Uint256, p: Uint256
    ) -> (r_x: Uint256, r_y: Uint256, r_res: Uint256) {
        alloc_locals;
        let (is_greater_than_zero) = uint256_lt(Uint256(low=0, high=0), y);
        if (is_greater_than_zero == FALSE) {
            return (r_x=x, r_y=y, r_res=res);
        }

        let (quotient, remainder) = uint256_unsigned_div_rem(y, Uint256(low=2, high=0));
        let (is_equal_to_one) = uint256_eq(remainder, Uint256(low=1, high=0));
        if (is_equal_to_one == FALSE) {
            let (x_res_quotient, x_res_quotient_high, x_res_remainder) = uint256_mul_div_mod(
                x, x, p
            );
            return uint256_mod_exp_recursive_call(x=x_res_remainder, y=quotient, res=res, p=p);
        } else {
            let (
                x_res_res_quotient, x_res_res_quotient_high, x_res_res_remainder
            ) = uint256_mul_div_mod(res, x, p);
            let (x_res_quotient, x_res_quotient_high, x_res_remainder) = uint256_mul_div_mod(
                x, x, p
            );
            return uint256_mod_exp_recursive_call(
                x=x_res_remainder, y=quotient, res=x_res_res_remainder, p=p
            );
        }
    }

    func calculate_mod_exp_gas{range_check_ptr: felt, bitwise_ptr: BitwiseBuiltin*}(
        b_size: Uint256, e_size: Uint256, m_size: Uint256, b: Uint256, e: Uint256, m: Uint256
    ) -> (gas_cost: felt) {
        alloc_locals;

        let (is_less_than) = uint256_lt(b_size, m_size);

        if (is_less_than == FALSE) {
            tempvar max_length = b_size;
        } else {
            tempvar max_length = m_size;
        }

        let (words_step_1, _) = uint256_add(max_length, Uint256(low=7, high=0));
        let (words, _) = uint256_unsigned_div_rem(words_step_1, Uint256(low=8, high=0));
        let (multiplication_complexity, carry) = uint256_mul(words, words);
        assert carry = Uint256(0, 0);

        let (is_less_than_33) = uint256_lt(e_size, Uint256(low=33, high=0));
        if (is_less_than_33 == FALSE) {
            let sub_step: Uint256 = uint256_sub(e_size, Uint256(low=32, high=0));

            let (local result, local carry) = uint256_mul(Uint256(low=8, high=0), sub_step);
            assert carry = Uint256(low=0, high=0);

            let (bitwise_high) = bitwise_and(e.high, 2 ** 128 - 1);
            let (bitwise_low) = bitwise_and(e.low, 2 ** 128 - 1);
            let e_bit_length = get_u256_bitlength(Uint256(low=bitwise_low, high=bitwise_high));

            let e_bit_length_uint256 = Uint256(low=e_bit_length, high=0);
            let (subtracted_e_bit_length) = uint256_sub(
                e_bit_length_uint256, Uint256(low=1, high=0)
            );

            let (addition, _) = uint256_add(result, subtracted_e_bit_length);

            tempvar iteration_count_res = addition;
            tempvar range_check_ptr = range_check_ptr;
            tempvar bitwise_ptr = bitwise_ptr;
        } else {
            let (is_zero) = uint256_eq(e, Uint256(low=0, high=0));
            if (is_zero == FALSE) {
                let u256_l = get_u256_bitlength(e);
                let inner_step = u256_l - 1;
                tempvar iteration_count = Uint256(low=inner_step, high=0);
                tempvar range_check_ptr = range_check_ptr;
                tempvar bitwise_ptr = bitwise_ptr;
            } else {
                tempvar iteration_count = Uint256(low=0, high=0);
                tempvar range_check_ptr = range_check_ptr;
                tempvar bitwise_ptr = bitwise_ptr;
            }
            tempvar iteration_count_res = iteration_count;
            tempvar range_check_ptr = range_check_ptr;
            tempvar bitwise_ptr = bitwise_ptr;
        }
        tempvar bitwise_ptr = bitwise_ptr;
        let another_var = iteration_count_res;
        let (mci, carry) = uint256_mul(multiplication_complexity, another_var);
        assert carry = Uint256(low=0, high=0);

        let (division_mci, _) = uint256_unsigned_div_rem(mci, Uint256(low=3, high=0));

        let (gas_is_greater_than) = uint256_lt(Uint256(low=200, high=0), division_mci);

        if (gas_is_greater_than == FALSE) {
            tempvar gas_cost = Uint256(low=GAS_COST_MOD_EXP, high=0);
        } else {
            tempvar gas_cost = division_mci;
        }
        let res = gas_cost.low;
        return (gas_cost=res);
    }
    // @author feltroidprime
    // Returns the number of bits in x.
    // Params:
    // - x: felt - Input value.
    // Assumptions for the caller:
    // - 0 <= x < 2^128
    // Returns:
    // - bit_length: felt - Number of bits in x.
    func get_felt_bitlength{range_check_ptr}(x: felt) -> felt {
        if (x == 0) {
            return 0;
        }
        alloc_locals;
        local bit_length;

        %{
            x = ids.x
            ids.bit_length = x.bit_length()
        %}
        if (bit_length == 128) {
            assert [range_check_ptr] = x - 2 ** 127;
            tempvar range_check_ptr = range_check_ptr + 1;
            return bit_length;
        } else {
            // Computes N=2^bit_length and n=2^(bit_length-1)
            // x is supposed to verify n = 2^(b-1) <= x < N = 2^bit_length <=> x has bit_length bits
            let N = pow2(bit_length);
            let n = pow2(bit_length - 1);
            assert [range_check_ptr] = bit_length;
            assert [range_check_ptr + 1] = 128 - bit_length;
            assert [range_check_ptr + 2] = N - x - 1;
            assert [range_check_ptr + 3] = x - n;
            tempvar range_check_ptr = range_check_ptr + 4;
            return bit_length;
        }
    }
    // @author feltroidprime
    // Returns 2**i for i in [0, 128]
    // Assumptions: i is in [0, 128].
    func pow2(i: felt) -> felt {
        let (_, pc) = get_fp_and_pc();

        pc_label:
        let data = pc + (powers - pc_label);

        let res = [data + i];

        return res;

        powers:
        dw 0x1;
        dw 0x2;
        dw 0x4;
        dw 0x8;
        dw 0x10;
        dw 0x20;
        dw 0x40;
        dw 0x80;
        dw 0x100;
        dw 0x200;
        dw 0x400;
        dw 0x800;
        dw 0x1000;
        dw 0x2000;
        dw 0x4000;
        dw 0x8000;
        dw 0x10000;
        dw 0x20000;
        dw 0x40000;
        dw 0x80000;
        dw 0x100000;
        dw 0x200000;
        dw 0x400000;
        dw 0x800000;
        dw 0x1000000;
        dw 0x2000000;
        dw 0x4000000;
        dw 0x8000000;
        dw 0x10000000;
        dw 0x20000000;
        dw 0x40000000;
        dw 0x80000000;
        dw 0x100000000;
        dw 0x200000000;
        dw 0x400000000;
        dw 0x800000000;
        dw 0x1000000000;
        dw 0x2000000000;
        dw 0x4000000000;
        dw 0x8000000000;
        dw 0x10000000000;
        dw 0x20000000000;
        dw 0x40000000000;
        dw 0x80000000000;
        dw 0x100000000000;
        dw 0x200000000000;
        dw 0x400000000000;
        dw 0x800000000000;
        dw 0x1000000000000;
        dw 0x2000000000000;
        dw 0x4000000000000;
        dw 0x8000000000000;
        dw 0x10000000000000;
        dw 0x20000000000000;
        dw 0x40000000000000;
        dw 0x80000000000000;
        dw 0x100000000000000;
        dw 0x200000000000000;
        dw 0x400000000000000;
        dw 0x800000000000000;
        dw 0x1000000000000000;
        dw 0x2000000000000000;
        dw 0x4000000000000000;
        dw 0x8000000000000000;
        dw 0x10000000000000000;
        dw 0x20000000000000000;
        dw 0x40000000000000000;
        dw 0x80000000000000000;
        dw 0x100000000000000000;
        dw 0x200000000000000000;
        dw 0x400000000000000000;
        dw 0x800000000000000000;
        dw 0x1000000000000000000;
        dw 0x2000000000000000000;
        dw 0x4000000000000000000;
        dw 0x8000000000000000000;
        dw 0x10000000000000000000;
        dw 0x20000000000000000000;
        dw 0x40000000000000000000;
        dw 0x80000000000000000000;
        dw 0x100000000000000000000;
        dw 0x200000000000000000000;
        dw 0x400000000000000000000;
        dw 0x800000000000000000000;
        dw 0x1000000000000000000000;
        dw 0x2000000000000000000000;
        dw 0x4000000000000000000000;
        dw 0x8000000000000000000000;
        dw 0x10000000000000000000000;
        dw 0x20000000000000000000000;
        dw 0x40000000000000000000000;
        dw 0x80000000000000000000000;
        dw 0x100000000000000000000000;
        dw 0x200000000000000000000000;
        dw 0x400000000000000000000000;
        dw 0x800000000000000000000000;
        dw 0x1000000000000000000000000;
        dw 0x2000000000000000000000000;
        dw 0x4000000000000000000000000;
        dw 0x8000000000000000000000000;
        dw 0x10000000000000000000000000;
        dw 0x20000000000000000000000000;
        dw 0x40000000000000000000000000;
        dw 0x80000000000000000000000000;
        dw 0x100000000000000000000000000;
        dw 0x200000000000000000000000000;
        dw 0x400000000000000000000000000;
        dw 0x800000000000000000000000000;
        dw 0x1000000000000000000000000000;
        dw 0x2000000000000000000000000000;
        dw 0x4000000000000000000000000000;
        dw 0x8000000000000000000000000000;
        dw 0x10000000000000000000000000000;
        dw 0x20000000000000000000000000000;
        dw 0x40000000000000000000000000000;
        dw 0x80000000000000000000000000000;
        dw 0x100000000000000000000000000000;
        dw 0x200000000000000000000000000000;
        dw 0x400000000000000000000000000000;
        dw 0x800000000000000000000000000000;
        dw 0x1000000000000000000000000000000;
        dw 0x2000000000000000000000000000000;
        dw 0x4000000000000000000000000000000;
        dw 0x8000000000000000000000000000000;
        dw 0x10000000000000000000000000000000;
        dw 0x20000000000000000000000000000000;
        dw 0x40000000000000000000000000000000;
        dw 0x80000000000000000000000000000000;
        dw 0x100000000000000000000000000000000;
    }
    // @credits feltroidprime
    // Returns the total number of bits in the uint256 number.
    // Assumptions :
    // - 0 <= x < 2^256
    // Returns:
    // - nbits: felt - Total number of bits in the uint256 number.
    func get_u256_bitlength{range_check_ptr}(x: Uint256) -> felt {
        if (x.high != 0) {
            let x_bit_high = get_felt_bitlength(x.high);
            return 128 + x_bit_high;
        } else {
            if (x.low != 0) {
                let x_bit_low = get_felt_bitlength(x.low);
                return x_bit_low;
            } else {
                return 0;
            }
        }
    }
}

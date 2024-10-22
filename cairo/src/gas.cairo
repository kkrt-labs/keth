from starkware.cairo.common.math import split_felt
from starkware.cairo.common.math_cmp import is_not_zero, is_nn, is_le_felt
from starkware.cairo.common.bool import FALSE
from starkware.cairo.common.uint256 import Uint256, uint256_lt

from src.model import model
from src.utils.uint256 import uint256_eq
from src.utils.utils import Helpers
from src.utils.maths import unsigned_div_rem, ceil32

const GAS_JUMPDEST = 1;
const GAS_BASE = 2;
const GAS_VERY_LOW = 3;
const GAS_STORAGE_SET = 20000;
const GAS_STORAGE_UPDATE = 5000;
const GAS_STORAGE_CLEAR_REFUND = 4800;
const GAS_LOW = 5;
const GAS_MID = 8;
const GAS_HIGH = 10;
const GAS_EXPONENTIATION = 10;
const GAS_EXPONENTIATION_PER_BYTE = 50;
const GAS_MEMORY = 3;
const GAS_KECCAK256 = 30;
const GAS_KECCAK256_WORD = 6;
const GAS_COPY = 3;
const GAS_BLOCK_HASH = 20;
const GAS_LOG = 375;
const GAS_LOG_DATA = 8;
const GAS_LOG_TOPIC = 375;
const GAS_CREATE = 32000;
const GAS_CODE_DEPOSIT = 200;
const GAS_ZERO = 0;
const GAS_NEW_ACCOUNT = 25000;
const GAS_CALL_VALUE = 9000;
const GAS_CALL_STIPEND = 2300;
const GAS_SELF_DESTRUCT = 5000;
const GAS_SELF_DESTRUCT_NEW_ACCOUNT = 25000;
const GAS_ECRECOVER = 3000;
const GAS_SHA256 = 60;
const GAS_SHA256_WORD = 12;
const GAS_RIPEMD160 = 600;
const GAS_RIPEMD160_WORD = 120;
const GAS_IDENTITY = 15;
const GAS_IDENTITY_WORD = 3;
const GAS_RETURN_DATA_COPY = 3;
const GAS_FAST_STEP = 5;
const GAS_BLAKE2_PER_ROUND = 1;
const GAS_COLD_SLOAD = 2100;
const GAS_COLD_ACCOUNT_ACCESS = 2600;
const GAS_WARM_ACCESS = 100;
const GAS_INIT_CODE_WORD_COST = 2;
const GAS_BLOBHASH_OPCODE = 3;
const GAS_POINT_EVALUATION = 50000;

namespace Gas {
    // @notive See https://github.com/ethereum/execution-specs/blob/master/src/ethereum/cancun/vm/gas.py#L253-L269
    func init_code_cost(init_code_length: felt) -> felt {
        let init_code_bytes = ceil32(init_code_length);
        let (init_code_words, _) = unsigned_div_rem(init_code_bytes, 32);
        return GAS_INIT_CODE_WORD_COST * init_code_words;
    }

    // @notice Compute the cost of the memory for a given words length.
    // @dev To avoid range_check overflow, we compute words_len / 512
    //      instead of words_len * words_len / 512. Then we recompute the
    //      resulting quotient: x^2 = 512q + r becomes
    //      x = 512 q0 + r0 => x^2 = 512(512 q0^2 + 2 q0 r0) + r0^2
    //      r0^2 = 512 q1 + r1
    //      x^2 = 512(512 q0^2 + 2 * q0 r0 + q1) + r1
    //      q = 512 * q0 * q0 + 2 q0 * r0 + q1
    // @param words_len The given number of words (bytes32).
    // @return cost The associated gas cost.
    func memory_cost{range_check_ptr}(words_len: felt) -> felt {
        let (q0, r0) = unsigned_div_rem(words_len, 512);
        let (q1, r1) = unsigned_div_rem(r0 * r0, 512);

        let memory_cost = 512 * q0 * q0 + 2 * q0 * r0 + q1 + (MEMORY * words_len);
        return memory_cost;
    }

    // @notice Compute the expansion cost of max_offset for the memory.
    // @dev Assumption max_offset < 2**133 necessary for unsigned_div_rem usage.
    // @param words_len The current length of the memory.
    // @param max_offset The target max_offset to be applied to the given memory.
    // @return cost The expansion gas cost: 0 if no expansion is triggered, and the new size of the memory
    func calculate_gas_extend_memory{range_check_ptr}(
        words_len: felt, max_offset: felt
    ) -> model.MemoryExpansion {
        alloc_locals;
        let is_memory_length_not_zero = is_not_zero(words_len);
        let current_memory_length = (words_len * 32 - 1) * is_memory_length_not_zero;
        let memory_expansion = is_le_felt(current_memory_length, max_offset);
        if (memory_expansion == FALSE) {
            let expansion = model.MemoryExpansion(cost=0, new_words_len=words_len);
            return expansion;
        }

        let prev_cost = memory_cost(words_len);
        let (new_words_len, _) = unsigned_div_rem(max_offset + 31, 32);
        let new_cost = memory_cost(new_words_len);

        let expansion_cost = new_cost - prev_cost;
        let expansion = model.MemoryExpansion(cost=expansion_cost, new_words_len=new_words_len);
        return expansion;
    }

    // @notive A saturated version of the memory_expansion_cost function
    // @dev Saturation at offset + size = 2^128.
    // @param words_len The current length of the memory as Uint256.
    // @param offset An offset to be applied to the given memory as Uint256.
    // @param size The size of the memory chunk.
    // @return cost The expansion gas cost: 0 if no expansion is triggered, and the new size of the memory
    func memory_expansion_cost_saturated{range_check_ptr}(
        words_len: felt, offset: Uint256, size: Uint256
    ) -> model.MemoryExpansion {
        let (is_zero) = uint256_eq(size, Uint256(low=0, high=0));
        if (is_zero != FALSE) {
            let expansion = model.MemoryExpansion(cost=0, new_words_len=words_len);
            return expansion;
        }

        let (q, _) = unsigned_div_rem(offset.low + size.low, 2 ** 32);
        if (offset.high == 0 and size.high == 0 and q == 0) {
            return calculate_gas_extend_memory(words_len, offset.low + size.low);
        }
        // Hardcoded value of cost(2**32) and size of 2**32 bytes = 2**27 words of 32 bytes
        // This offset would produce an OOG error in any case
        let expansion = model.MemoryExpansion(cost=MEMORY_COST_U32, new_words_len=2 ** 27);
        return expansion;
    }

    // @notice Given two memory chunks, compute the maximum expansion cost
    //  based on the maximum offset reached by each chunks.
    // @dev Memory expansion cost is computed over the `low` parts of
    // the offsets and sizes.  In the second step, we check whether the `high`
    // parts are non-zero and if so, we add the cost of expanding the memory by
    // 2**128 words (saturating).
    // @param words_len The current length of the memory as felt252.
    // @param offset_1 The offset of the first memory chunk as Uint256.
    // @param size_1 The size of the first memory chunk as Uint256.
    // @param offset_2 The offset of the second memory chunk as Uint256.
    // @param size_2 The size of the second memory chunk as Uint256.
    // @return cost The expansion gas cost for chunk who's ending offset is the largest and the new size of the memory
    func max_memory_expansion_cost{range_check_ptr}(
        words_len: felt, offset_1: Uint256*, size_1: Uint256*, offset_2: Uint256*, size_2: Uint256*
    ) -> model.MemoryExpansion {
        alloc_locals;

        let (is_zero_1) = uint256_eq([size_1], Uint256(0, 0));
        let (is_zero_2) = uint256_eq([size_2], Uint256(0, 0));
        tempvar both_zero = is_zero_1 * is_zero_2;
        jmp no_expansion if both_zero != 0;

        tempvar is_not_saturated = Helpers.is_zero(offset_1.high) * Helpers.is_zero(size_1.high) *
            Helpers.is_zero(offset_2.high) * Helpers.is_zero(size_2.high);
        tempvar is_saturated = 1 - is_not_saturated;
        tempvar range_check_ptr = range_check_ptr;
        jmp expansion_cost_saturated if is_saturated != 0;

        let max_offset_1 = (1 - is_zero_1) * (offset_1.low + size_1.low);
        let max_offset_2 = (1 - is_zero_2) * (offset_2.low + size_2.low);
        let max_expansion_is_2 = is_le_felt(max_offset_1, max_offset_2);
        let max_offset = max_offset_1 * (1 - max_expansion_is_2) + max_offset_2 *
            max_expansion_is_2;
        let (q, _) = unsigned_div_rem(max_offset, 2 ** 32);
        tempvar range_check_ptr = range_check_ptr;
        jmp expansion_cost_saturated if q != 0;

        let expansion = calculate_gas_extend_memory(words_len, max_offset);
        let expansion = model.MemoryExpansion(
            cost=expansion.cost, new_words_len=expansion.new_words_len
        );
        return expansion;

        no_expansion:
        let range_check_ptr = [fp - 8];
        let expansion = model.MemoryExpansion(cost=0, new_words_len=words_len);
        return expansion;

        expansion_cost_saturated:
        let range_check_ptr = [ap - 1];
        // Hardcoded value of cost(2**32) and size of 2**32 bytes = 2**27 words of 32 bytes
        // This offset would produce an OOG error in any case
        let expansion = model.MemoryExpansion(cost=MEMORY_COST_U32, new_words_len=2 ** 27);
        return expansion;
    }

    // @notice Computes the base gas of a message call.
    // @dev This should be called after having withdrawn the gas relative to the
    // memory expansion and eventual extra gas costs.
    // @param gas_param The gas parameter of the message call, from the Stack.
    // @param gas_left The gas left in the current execution frame.
    // @return gas The base gas of the message call.
    func compute_message_call_gas{range_check_ptr}(gas_param: Uint256, gas_left: felt) -> felt {
        alloc_locals;
        let (quotient, _) = unsigned_div_rem(gas_left, 64);
        tempvar max_allowed_gas = gas_left - quotient;
        let (max_allowed_high, max_allowed_low) = split_felt(max_allowed_gas);
        tempvar max_allowed = Uint256(low=max_allowed_low, high=max_allowed_high);
        let (is_gas_param_lower) = uint256_lt(gas_param, max_allowed);

        // The message gas is the minimum between the gas param and the remaining gas left.
        if (is_gas_param_lower != FALSE) {
            // If gas is lower, it means that it fits in a felt and this is safe
            tempvar gas = gas_param.low + 2 ** 128 * gas_param.high;
            return gas;
        }
        return max_allowed.low;
    }
}

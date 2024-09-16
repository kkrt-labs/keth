from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.math_cmp import is_nn
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE, TRUE

from src.errors import Errors
from src.account import Account
from src.utils.utils import Helpers

const CALL_CONTRACT_SOLIDITY_SELECTOR = 0xb3eb2c1b;

// TODO: compute acceptable EVM gas values for Cairo execution
const CAIRO_PRECOMPILE_GAS = 10000;
const CAIRO_MESSAGE_GAS = 5000;

namespace KakarotPrecompiles {
    // @notice Executes a cairo contract/class.
    // @param input_len The length of the input in bytes.
    // @param input The input data.
    // @param caller_address The address of the caller of the precompile. Delegatecall rules apply.
    func cairo_precompile{
        pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
    }(input_len: felt, input: felt*, caller_address: felt) -> (
        output_len: felt, output: felt*, gas_used: felt, reverted: felt
    ) {
        alloc_locals;

        // Input must be at least 4 + 3*32 bytes long.
        let is_input_invalid = is_nn(99 - input_len);
        if (is_input_invalid != 0) {
            let (revert_reason_len, revert_reason) = Errors.outOfBoundsRead();
            return (revert_reason_len, revert_reason, CAIRO_PRECOMPILE_GAS, TRUE);
        }

        // Input is formatted as:
        // [selector: bytes4][starknet_address: bytes32][starknet_selector:bytes32][data_offset: bytes32][data_len: bytes32][data: bytes[]]

        // Load selector from first 4 bytes of input.
        let selector = Helpers.bytes4_to_felt(input);
        let args_ptr = input + 4;

        // Load address and cairo selector called
        // Safe to assume that the 32 bytes in input do not overflow a felt (whitelisted precompiles)
        let to_starknet_address = Helpers.bytes32_to_felt(args_ptr);

        let starknet_selector_ptr = args_ptr + 32;
        let starknet_selector = Helpers.bytes32_to_felt(starknet_selector_ptr);

        let data_offset_ptr = args_ptr + 64;
        let data_offset = Helpers.bytes32_to_felt(data_offset_ptr);
        let data_len_ptr = args_ptr + data_offset;

        // Load input data by packing all
        // If the input data is larger than the size of a felt, it will wrap around the felt size.
        let data_words_len = Helpers.bytes32_to_felt(data_len_ptr);
        let data_bytes_len = data_words_len * 32;
        let data_ptr = data_len_ptr + 32;
        let (data_len, data) = Helpers.load_256_bits_array(data_bytes_len, data_ptr);

        let (revert_reason_len, revert_reason) = Errors.invalidCairoSelector();
        return (revert_reason_len, revert_reason, CAIRO_PRECOMPILE_GAS, TRUE);
    }
}

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin, KeccakBuiltin

from src.model import model
from src.utils.utils import Helpers
from src.memory import Memory
from src.evm import EVM

// @title DataCopy precompile
// @custom:precompile
// @custom:address 0x04
// @notice This precompile serves as a cheaper way to copy data in memory
namespace PrecompileDataCopy {
    const PRECOMPILE_ADDRESS = 0x04;
    const GAS_COST_DATACOPY = 15;

    // @notice Run the precompile.
    // @param input_len The length of input array.
    // @param input The input array.
    // @return output_len The output length.
    // @return output The output array.
    // @return gas_used The gas usage of precompile.
    func run{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        keccak_ptr: KeccakBuiltin*,
    }(_address: felt, input_len: felt, input: felt*) -> (
        output_len: felt, output: felt*, gas_used: felt, reverted: felt
    ) {
        let (minimum_word_size) = Helpers.minimum_word_count(input_len);
        return (input_len, input, 3 * minimum_word_size + GAS_COST_DATACOPY, 0);
    }
}

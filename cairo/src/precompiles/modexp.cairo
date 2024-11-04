from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.alloc import alloc

from src.utils.utils import Helpers
from src.utils.modexp.modexp_utils import ModExpHelpersUint256
from src.utils.bytes import uint256_to_bytes

// @title ModExpUint256 MVP Precompile related functions.
// @notice It is an MVP implementation since it only supports uint256 numbers with m_size<=16 and not bigint which requires bigint library in cairo 0.10.
// @author @dragan2234
// @custom:namespace PrecompileModExpUint256
namespace PrecompileModExpUint256 {
    const PRECOMPILE_ADDRESS = 0x05;
    const MOD_EXP_BYTES_LEN = 32;

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
        alloc_locals;

        let b_size: Uint256 = Helpers.bytes32_to_uint256(input);
        let e_size: Uint256 = Helpers.bytes32_to_uint256(input + MOD_EXP_BYTES_LEN);
        let m_size: Uint256 = Helpers.bytes32_to_uint256(input + MOD_EXP_BYTES_LEN * 2);
        let b: Uint256 = Helpers.bytes_to_uint256(b_size.low, input + MOD_EXP_BYTES_LEN * 3);
        let e: Uint256 = Helpers.bytes_to_uint256(
            e_size.low, input + MOD_EXP_BYTES_LEN * 3 + b_size.low
        );
        let m: Uint256 = Helpers.bytes_to_uint256(
            m_size.low, input + MOD_EXP_BYTES_LEN * 3 + b_size.low + e_size.low
        );
        with_attr error_message("Kakarot: modexp failed") {
            let (result) = ModExpHelpersUint256.uint256_mod_exp(b, e, m);
        }
        let bytes: felt* = alloc();
        let bytes_len = uint256_to_bytes(bytes, result);

        let (gas_cost) = ModExpHelpersUint256.calculate_mod_exp_gas(
            b_size, m_size, e_size, b, e, m
        );

        return (bytes_len, bytes, gas_cost, 0);
    }
}

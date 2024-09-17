from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.memset import memset

from src.utils.utils import Helpers
from src.interfaces.interfaces import ICairo1Helpers

// @title P256Verify precompile related functions.
// @notice This file contains the logic required to run the ec_recover precompile
// using Starkware's cairo_secp library
// @author @clementwalter
// @custom:namespace PrecompileEcRecover
namespace PrecompileP256Verify {
    const PRECOMPILE_ADDRESS = 0x100;
    const GAS_COST_P256_VERIFY = 3450;

    // @notice Run the precompile.
    // @param input_len The length of input array.
    // @param input The input array.
    // @return output_len The output length.
    // @return output The output array.
    // @return gas_used The gas usage of precompile.
    func run{pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
        _address: felt, input_len: felt, input: felt*
    ) -> (output_len: felt, output: felt*, gas_used: felt, reverted: felt) {
        alloc_locals;

        let (output) = alloc();
        if (input_len != 160) {
            return (0, output, GAS_COST_P256_VERIFY, 0);
        }

        let msg_hash = Helpers.bytes32_to_uint256(input);
        let r = Helpers.bytes32_to_uint256(input + 32);
        let s = Helpers.bytes32_to_uint256(input + 64);
        let x = Helpers.bytes32_to_uint256(input + 96);
        let y = Helpers.bytes32_to_uint256(input + 128);

        let (is_valid) = ICairo1Helpers.verify_signature_secp256r1(
            msg_hash=msg_hash, r=r, s=s, x=x, y=y
        );

        if (is_valid == 0) {
            return (0, output, GAS_COST_P256_VERIFY, 0);
        }

        memset(output, 0, 31);
        assert output[31] = 1;
        return (32, output, GAS_COST_P256_VERIFY, 0);
    }
}

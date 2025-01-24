from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.alloc import alloc

from src.curve.alt_bn128 import alt_bn128
from src.curve.g1_point import G1Point
from src.curve.ec_ops import ec_add
from src.utils.utils import Helpers
from src.utils.bytes import uint256_to_bytes32
from src.utils.uint384 import UInt384, uint256_to_uint384, uint384_to_uint256

namespace PrecompileEcAdd {
    const PRECOMPILE_ADDRESS = 0x06;
    const GAS_COST_EC_ADD = 150;
    const G1POINT_BYTES_LEN = 32;

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

        let x0_u256 = Helpers.bytes32_to_uint256(input);
        let y0_u256 = Helpers.bytes32_to_uint256(input + G1POINT_BYTES_LEN);
        let x1_u256 = Helpers.bytes32_to_uint256(input + G1POINT_BYTES_LEN * 2);
        let y1_u256 = Helpers.bytes32_to_uint256(input + G1POINT_BYTES_LEN * 3);

        let x0 = uint256_to_uint384(x0_u256);
        let y0 = uint256_to_uint384(y0_u256);
        let x1 = uint256_to_uint384(x1_u256);
        let y1 = uint256_to_uint384(y1_u256);
        let p = G1Point(x0, y0);
        let q = G1Point(x1, y1);

        tempvar g_ptr = UInt384(alt_bn128.G0, alt_bn128.G1, alt_bn128.G2, alt_bn128.G3);
        tempvar a_ptr = UInt384(alt_bn128.A0, alt_bn128.A1, alt_bn128.A2, alt_bn128.A3);
        tempvar modulus_ptr = UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3);

        with_attr error_message("Kakarot: ec_add failed") {
            let result: G1Point = ec_add(p, q, g_ptr, a_ptr, modulus_ptr);
        }

        let x_u256 = uint384_to_uint256(result.x);
        let y_u256 = uint384_to_uint256(result.y);

        let (output) = alloc();
        uint256_to_bytes32(output, x_u256);
        uint256_to_bytes32(output + G1POINT_BYTES_LEN, y_u256);

        return (G1POINT_BYTES_LEN * 2, output, GAS_COST_EC_ADD, 0);
    }
}

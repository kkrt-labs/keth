from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.builtin_keccak.keccak import keccak_uint256s_bigend
from starkware.cairo.common.bool import FALSE
from starkware.cairo.common.math_cmp import RC_BOUND
from starkware.cairo.common.cairo_secp.ec import EcPoint
from starkware.cairo.common.cairo_secp.bigint import BigInt3
from starkware.cairo.common.cairo_secp.signature import (
    recover_public_key,
    public_key_point_to_eth_address,
)
from starkware.cairo.common.uint256 import Uint256, uint256_reverse_endian
from starkware.cairo.common.cairo_secp.bigint import bigint_to_uint256
from starkware.cairo.common.memset import memset

from src.errors import Errors
from src.interfaces.interfaces import ICairo1Helpers
from src.utils.utils import Helpers
from src.utils.array import slice
from src.utils.maths import unsigned_div_rem

// @title EcRecover Precompile related functions.
// @notice This file contains the logic required to run the ec_recover precompile
// using Starkware's cairo_secp library
// @author @clementwalter
// @custom:namespace PrecompileEcRecover
namespace PrecompileEcRecover {
    const PRECOMPILE_ADDRESS = 0x01;
    const GAS_COST_EC_RECOVER = 3000;

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

        let (input_padded) = alloc();
        slice(input_padded, input_len, input, 0, 4 * 32);

        let v_uint256 = Helpers.bytes32_to_uint256(input_padded + 32);
        let v = Helpers.uint256_to_felt(v_uint256);

        if ((v - 27) * (v - 28) != 0) {
            let (output) = alloc();
            return (0, output, GAS_COST_EC_RECOVER, 0);
        }

        let msg_hash = Helpers.bytes_to_uint256(32, input_padded);
        let r = Helpers.bytes_to_uint256(32, input_padded + 32 * 2);
        let s = Helpers.bytes_to_uint256(32, input_padded + 32 * 3);

        // v - 27, see recover_public_key comment
        let (success, recovered_address) = ICairo1Helpers.recover_eth_address(
            msg_hash=msg_hash, r=r, s=s, y_parity=v - 27
        );

        if (success == 0) {
            let (output) = alloc();
            return (0, output, GAS_COST_EC_RECOVER, 0);
        }

        let (output) = alloc();
        memset(output, 0, 12);
        Helpers.split_word(recovered_address, 20, output + 12);

        return (32, output, GAS_COST_EC_RECOVER, 0);
    }
}

namespace EcRecoverHelpers {
    func ec_point_equal(point_0: EcPoint, point_1: EcPoint) -> (is_equal: felt) {
        if (point_0.x.d0 == point_1.x.d0 and point_0.y.d0 == point_1.y.d0 and
            point_0.x.d1 == point_1.x.d1 and point_0.y.d1 == point_1.y.d1 and
            point_0.x.d2 == point_1.x.d2 and point_0.y.d2 == point_1.y.d2) {
            return (is_equal=1);
        }
        return (is_equal=0);
    }

    // @notice Convert a public key point to the corresponding Ethereum address.
    func public_key_point_to_eth_address{
        pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
    }(public_key_point: EcPoint) -> (eth_address: felt) {
        alloc_locals;
        let (local elements: Uint256*) = alloc();
        let (x_uint256: Uint256) = bigint_to_uint256(public_key_point.x);
        assert elements[0] = x_uint256;
        let (y_uint256: Uint256) = bigint_to_uint256(public_key_point.y);
        assert elements[1] = y_uint256;

        let (point_hash) = keccak_uint256s_bigend(n_elements=2, elements=elements);

        // The Ethereum address is the 20 least significant bytes of the keccak of the public key.
        let (high_high, high_low) = unsigned_div_rem(point_hash.high, 2 ** 32);
        return (eth_address=point_hash.low + RC_BOUND * high_low);
    }
}

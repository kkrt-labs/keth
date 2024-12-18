from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import (
    HashBuiltin,
    BitwiseBuiltin,
    KeccakBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
)
from starkware.cairo.common.builtin_keccak.keccak import keccak_uint256s_bigend
from starkware.cairo.common.bool import FALSE
from starkware.cairo.common.math_cmp import RC_BOUND
from starkware.cairo.common.cairo_secp.ec import EcPoint
from starkware.cairo.common.cairo_secp.bigint import BigInt3
from starkware.cairo.common.cairo_secp.signature import recover_public_key
from starkware.cairo.common.uint256 import Uint256, uint256_reverse_endian, uint256_lt
from starkware.cairo.common.cairo_secp.bigint import bigint_to_uint256, uint256_to_bigint
from starkware.cairo.common.memset import memset

from src.errors import Errors
from src.utils.uint256 import uint256_eq, uint256_to_uint384
from src.utils.utils import Helpers
from src.utils.array import slice
from src.utils.signature import Signature
from src.utils.maths import unsigned_div_rem

// @title EcRecover Precompile related functions.
// @notice This file contains the logic required to run the ec_recover precompile
// using Starkware's cairo_secp library
// @author @clementwalter
// @custom:namespace PrecompileEcRecover
namespace PrecompileEcRecover {
    const PRECOMPILE_ADDRESS = 0x01;
    const GAS_COST_EC_RECOVER = 3000;

    const SECP256K1N_HIGH = 0xfffffffffffffffffffffffffffffffe;
    const SECP256K1N_LOW = 0xbaaedce6af48a03bbfd25e8cd0364141;

    // @notice Run the precompile.
    // @param input_len The length of input array.
    // @param input The input array.
    // @return output_len The output length.
    // @return output The output array.
    // @return gas_used The gas usage of precompile.
    func run{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        range_check96_ptr: felt*,
        add_mod_ptr: ModBuiltin*,
        mul_mod_ptr: ModBuiltin*,
        bitwise_ptr: BitwiseBuiltin*,
        keccak_ptr: KeccakBuiltin*,
        poseidon_ptr: PoseidonBuiltin*,
    }(_address: felt, input_len: felt, input: felt*) -> (
        output_len: felt, output: felt*, gas_used: felt, reverted: felt
    ) {
        alloc_locals;

        let (input_padded) = alloc();
        slice(input_padded, input_len, input, 0, 4 * 32);

        let v_uint256 = Helpers.bytes32_to_uint256(input_padded + 32);
        let v = Helpers.uint256_to_felt(v_uint256);

        if ((v - 27) * (v - 28) != 0) {
            let (output) = alloc();
            return (0, output, GAS_COST_EC_RECOVER, 0);
        }

        let msg_hash_uint256 = Helpers.bytes32_to_uint256(input_padded);
        let msg_hash_uint384 = uint256_to_uint384(msg_hash_uint256);
        let r = Helpers.bytes_to_uint256(32, input_padded + 32 * 2);
        let s = Helpers.bytes_to_uint256(32, input_padded + 32 * 3);

        let SECP256K1N = Uint256(low=SECP256K1N_LOW, high=SECP256K1N_HIGH);
        let (is_valid_upper_r) = uint256_lt(r, SECP256K1N);
        let (is_valid_upper_s) = uint256_lt(s, SECP256K1N);
        let is_valid_upper_bound = is_valid_upper_r * is_valid_upper_s;
        if (is_valid_upper_bound == FALSE) {
            let (output) = alloc();
            return (0, output, GAS_COST_EC_RECOVER, 0);
        }

        let (is_invalid_lower_r) = uint256_eq(r, Uint256(low=0, high=0));
        let (is_invalid_lower_s) = uint256_eq(s, Uint256(low=0, high=0));
        let is_invalid_lower_bound = is_invalid_lower_r + is_invalid_lower_s;
        if (is_invalid_lower_bound != FALSE) {
            let (output) = alloc();
            return (0, output, GAS_COST_EC_RECOVER, 0);
        }

        let r_uint384 = uint256_to_uint384(r);
        let s_uint384 = uint256_to_uint384(s);
        let (success, recovered_address) = Signature.try_recover_eth_address(
            msg_hash_uint384, r_uint384, s_uint384, v - 27
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
}

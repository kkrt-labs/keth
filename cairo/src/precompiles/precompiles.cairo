from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.math_cmp import is_nn, is_not_zero, is_in_range
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE
from starkware.cairo.common.memcpy import memcpy

from src.errors import Errors
from src.precompiles.blake2f import PrecompileBlake2f
from src.precompiles.datacopy import PrecompileDataCopy
from src.precompiles.ec_recover import PrecompileEcRecover
from src.precompiles.p256verify import PrecompileP256Verify
from src.precompiles.ripemd160 import PrecompileRIPEMD160
from src.precompiles.sha256 import PrecompileSHA256
from src.utils.utils import Helpers

const LAST_ETHEREUM_PRECOMPILE_ADDRESS = 0x0a;

// @title Precompile related functions.
namespace Precompiles {
    // @notice Return whether the address is a precompile address.
    // @dev Ethereum precompiles are in range [0x01, 0x0a]
    func is_precompile{range_check_ptr}(address: felt) -> felt {
        alloc_locals;
        return is_not_zero(address) * (is_nn(LAST_ETHEREUM_PRECOMPILE_ADDRESS - address));
    }

    // @notice Executes associated function of precompiled evm_address.
    // @dev This function uses an internal jump table to execute the corresponding precompile impmentation.
    // @param precompile_address The precompile evm_address.
    // @param input_len The length of the input array.
    // @param input The input array.
    // @return output_len The output length.
    // @return output The output array.
    // @return gas_used The gas usage of precompile.
    // @return reverted Whether the precompile ran successfully or not
    func exec_precompile{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        keccak_ptr: KeccakBuiltin*,
    }(precompile_address: felt, input_len: felt, input: felt*) -> (
        output_len: felt, output: felt*, gas_used: felt, reverted: felt
    ) {
        // Compute the corresponding offset in the jump table:
        // count 1 for "next line" and 3 steps per index: call, precompile, ret
        let index = precompile_address;
        tempvar offset = 1 + 3 * index;

        // Prepare arguments
        [ap] = pedersen_ptr, ap++;
        [ap] = range_check_ptr, ap++;
        [ap] = bitwise_ptr, ap++;
        [ap] = keccak_ptr, ap++;
        [ap] = precompile_address, ap++;
        [ap] = input_len, ap++;
        [ap] = input, ap++;

        // call precompile precompile_address
        jmp rel offset;
        call invalid_precompile_call;  // 0x0
        ret;
        call PrecompileEcRecover.run;  // 0x1 EC_RECOVER
        ret;
        call not_implemented_precompile;  // 0x2 SHA2-256
        ret;
        call PrecompileRIPEMD160.run;  // 0x3 RIPEMD-160
        ret;
        call PrecompileDataCopy.run;  // 0x4 DATA_COPY
        ret;
        call not_implemented_precompile;  // 0x5 MODEXP
        ret;
        call not_implemented_precompile;  // 0x6 EC_ADD
        ret;
        call not_implemented_precompile;  // 0x7 EC_MUL
        ret;
        call not_implemented_precompile;  // 0x8 EC_PAIRING
        ret;
        call PrecompileBlake2f.run;  // 0x9 BLAKE2-F
        ret;
        call not_implemented_precompile;  // 0x0a: POINT_EVALUATION_PRECOMPILE
        ret;
    }

    // @notice Precompile called but is not valid. Should never be reached as checks must have been done before.
    // @dev Always fails the execution.
    func invalid_precompile_call{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        keccak_ptr: KeccakBuiltin*,
    }(evm_address: felt, input_len: felt, input: felt*) -> () {
        with_attr error_message("Precompile called but does not exist") {
            assert 0 = 1;
        }
        return ();
    }

    // @notice A placeholder for precompile that are not implemented yet.
    // @dev Halts execution.
    // @param evm_address The evm_address.
    // @param input_len The length of the input array.
    // @param input The input array.
    func not_implemented_precompile{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        keccak_ptr: KeccakBuiltin*,
    }(evm_address: felt, input_len: felt, input: felt*) -> (
        output_len: felt, output: felt*, gas_used: felt, reverted: felt
    ) {
        let (revert_reason_len, revert_reason) = Errors.notImplementedPrecompile(evm_address);
        return (revert_reason_len, revert_reason, 0, Errors.EXCEPTIONAL_HALT);
    }
}

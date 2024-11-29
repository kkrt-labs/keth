from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.math_cmp import is_nn, is_not_zero, is_in_range
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE
from starkware.cairo.common.memcpy import memcpy

from src.errors import Errors
from src.precompiles.blake2f import PrecompileBlake2f
from src.precompiles.kakarot_precompiles import KakarotPrecompiles
from src.precompiles.datacopy import PrecompileDataCopy
from src.precompiles.ec_recover import PrecompileEcRecover
from src.precompiles.p256verify import PrecompileP256Verify
from src.precompiles.ripemd160 import PrecompileRIPEMD160
from src.precompiles.sha256 import PrecompileSHA256
from src.precompiles.precompiles_helpers import (
    PrecompilesHelpers,
    LAST_ETHEREUM_PRECOMPILE_ADDRESS,
    FIRST_ROLLUP_PRECOMPILE_ADDRESS,
    FIRST_KAKAROT_PRECOMPILE_ADDRESS,
)
from src.utils.utils import Helpers

// @title Precompile related functions.
namespace Precompiles {
    // @notice Executes associated function of precompiled evm_address.
    // @dev This function uses an internal jump table to execute the corresponding precompile impmentation.
    // @param precompile_address The precompile evm_address.
    // @param input_len The length of the input array.
    // @param input The input array.
    // @param caller_code_address The address of the code of the contract that calls the precompile.
    // @param caller_address The address of the caller of the precompile. Delegatecall rules apply.
    // @return output_len The output length.
    // @return output The output array.
    // @return gas_used The gas usage of precompile.
    // @return reverted Whether the precompile ran successfully or not
    func exec_precompile{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        keccak_ptr: KeccakBuiltin*,
    }(
        precompile_address: felt,
        input_len: felt,
        input: felt*,
        caller_code_address: felt,
        caller_address: felt,
    ) -> (output_len: felt, output: felt*, gas_used: felt, reverted: felt) {
        let is_eth_precompile = is_nn(LAST_ETHEREUM_PRECOMPILE_ADDRESS - precompile_address);
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
        jmp eth_precompile if is_eth_precompile != 0;

        let is_rollup_precompile_ = PrecompilesHelpers.is_rollup_precompile(precompile_address);
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
        jmp rollup_precompile if is_rollup_precompile_ != 0;

        let is_kakarot_precompile_ = PrecompilesHelpers.is_kakarot_precompile(precompile_address);
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
        jmp kakarot_precompile if is_kakarot_precompile_ != 0;
        jmp unauthorized_call;

        eth_precompile:
        tempvar index = precompile_address;
        jmp call_precompile;

        rollup_precompile:
        tempvar index = (LAST_ETHEREUM_PRECOMPILE_ADDRESS + 1) + (
            precompile_address - FIRST_ROLLUP_PRECOMPILE_ADDRESS
        );
        jmp call_precompile;

        unauthorized_call:
        // Prepare arguments if none of the above conditions are met
        [ap] = pedersen_ptr, ap++;
        [ap] = range_check_ptr, ap++;
        [ap] = bitwise_ptr, ap++;
        [ap] = keccak_ptr, ap++;
        call unauthorized_precompile;
        ret;

        call_precompile:
        // Compute the corresponding offset in the jump table:
        // count 1 for "next line" and 3 steps per index: call, precompile, ret
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
        call unknown_precompile;  // 0x0
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
        // Rollup precompiles. Offset must have been computed appropriately,
        // based on the address of the precompile and the last ethereum precompile
        call PrecompileP256Verify.run;  // offset 0x0b: precompile 0x100
        ret;

        kakarot_precompile:
        tempvar index = precompile_address - FIRST_KAKAROT_PRECOMPILE_ADDRESS;
        tempvar offset = 1 + 3 * index;

        // Prepare arguments
        [ap] = pedersen_ptr, ap++;
        [ap] = range_check_ptr, ap++;
        [ap] = bitwise_ptr, ap++;
        [ap] = keccak_ptr, ap++;
        [ap] = input_len, ap++;
        [ap] = input, ap++;
        [ap] = caller_address, ap++;

        // Kakarot precompiles. Offset must have been computed appropriately,
        // based on the total number of kakarot precompiles
        jmp rel offset;
        call KakarotPrecompiles.cairo_precompile;  // offset 0x0c: precompile 0x75001
        ret;
    }

    // @notice A placeholder for attempts to call a precompile without permissions
    // @dev Halts execution.
    // @param evm_address The evm_address.
    // @param input_len The length of the input array.
    // @param input The input array.
    func unauthorized_precompile{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        keccak_ptr: KeccakBuiltin*,
    }() -> (output_len: felt, output: felt*, gas_used: felt, reverted: felt) {
        let (revert_reason_len, revert_reason) = Errors.unauthorizedPrecompile();
        return (revert_reason_len, revert_reason, 0, Errors.REVERT);
    }

    // @notice A placeholder for precompile that don't exist.
    // @dev Halts execution.
    // @param evm_address The evm_address.
    // @param input_len The length of the input array.
    // @param input The input array.
    func unknown_precompile{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        keccak_ptr: KeccakBuiltin*,
    }(evm_address: felt, input_len: felt, input: felt*) -> (
        output_len: felt, output: felt*, gas_used: felt, reverted: felt
    ) {
        let (revert_reason_len, revert_reason) = Errors.unknownPrecompile(evm_address);
        return (revert_reason_len, revert_reason, 0, Errors.EXCEPTIONAL_HALT);
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

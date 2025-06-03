from starkware.cairo.common.registers import get_label_location
from starkware.cairo.common.math_cmp import is_le_felt
from starkware.cairo.common.math import split_felt
from ethereum.utils.numeric import divmod
from ethereum.prague.vm.precompiled_contracts.identity import identity
from ethereum.prague.vm.precompiled_contracts.sha256 import sha256
from ethereum.prague.vm.precompiled_contracts.modexp import modexp
from ethereum.prague.vm.precompiled_contracts.alt_bn128 import (
    alt_bn128_pairing_check,
    alt_bn128_add,
    alt_bn128_mul,
)
from ethereum.prague.vm.precompiled_contracts.ecrecover import ecrecover
from ethereum.prague.vm.precompiled_contracts.blake2f import blake2f
from ethereum.prague.vm.precompiled_contracts.point_evaluation import point_evaluation
from ethereum.prague.vm.precompiled_contracts.ripemd160 import ripemd160
from ethereum.prague.vm.precompiled_contracts.bls12_381.bls12_381_g1 import (
    bls12_g1_add,
    bls12_g1_msm,
    bls12_map_fp_to_g1,
)
from ethereum.prague.vm.precompiled_contracts.bls12_381.bls12_381_g2 import (
    bls12_g2_add,
    bls12_g2_msm,
    bls12_map_fp2_to_g2,
)
from ethereum.prague.vm.precompiled_contracts.bls12_381.bls12_381_pairing import bls12_pairing
from cairo_core.control_flow import raise

// currently 17 precompiles.
const N_PRECOMPILES = 17;
const HIGHEST_PRECOMPILE_LEADING_BYTE = 0x11;

// count 3 steps per index: precompile_address, call, precompile_fn
const MAX_OFFSET = N_PRECOMPILES * 3;

// @notice A table of (address, function ptr) for precompiled contracts
// @dev Meant to be used with an `index` provided by the prover, that cannot be trusted.
// @dev The address returned will need to be verified by the caller.
// @param index The index of the address precompiled contract in the table (3 * number)
// @param address The address of the precompiled contract called
// @return (0, 0) if the address is not a precompile, otherwise (address, function_ptr)
func precompile_table_lookup{range_check_ptr}(address: felt) -> (felt, felt) {
    alloc_locals;

    // Check if address is a valid precompile
    // Addresses are little-endian, we want easy comparison to 0x01-0x11 value, take the leading byte
    let (address_high, address_low) = split_felt(address);
    if (address_low != 0) {
        return (0, 0);
    }
    let (leading_byte, remaining) = divmod(address_high, 2 ** (3 * 8));
    // Only the leading byte should be non-zero
    if (leading_byte == 0) {
        return (0, 0);
    }
    if (remaining != 0) {
        return (0, 0);
    }
    let addr_too_high = is_le_felt(HIGHEST_PRECOMPILE_LEADING_BYTE + 1, leading_byte);
    if (addr_too_high != 0) {
        return (0, 0);
    }

    // Provided the address is a valid precompile, get its index from the precompile table
    // This enables non-sequential precompile addresses for the future
    let (local precompiled_contracts_location: felt*) = get_label_location(PRE_COMPILED_CONTRACTS);

    tempvar index;
    %{ precompile_index_from_address %}

    let is_valid_index = is_le_felt(index, MAX_OFFSET);
    with_attr error_message("precompile_table_lookup: index out of bounds") {
        assert is_valid_index = 1;
    }

    // // at index: address, at index+1: call, at index+2: fn
    let table_address = precompiled_contracts_location[index];
    // Soundness: verify the fn we got from the jump table is the one associated with the address
    with_attr error_message("precompile_table_lookup: address mismatch") {
        assert table_address = address;
    }

    // To get the absolute fn ptr:
    // - get the fn ptr relative to the current instruction (precompiled_contracts_location[index + 2])
    // - add the absolute address of the current instruction (precompiled_contracts_location + index + 1) to the relative fn ptr
    let table_fn = cast(
        precompiled_contracts_location + index + 1 + precompiled_contracts_location[index + 2], felt
    );

    return (table_address, table_fn);

    // In the following table:
    // - index i is the address of the precompiled contract
    // - index i+1 is the call instruction, a hack that allows us to get the function pointer of the
    // precompiled contract at compile time
    // - index i+2 is the function pointer of the precompiled contract
    PRE_COMPILED_CONTRACTS:
    dw 0x0100000000000000000000000000000000000000;
    call ecrecover;  // ECRECOVER
    dw 0x0200000000000000000000000000000000000000;
    call sha256;  // SHA256
    dw 0x0300000000000000000000000000000000000000;
    call ripemd160;  // RIPEMD160
    dw 0x0400000000000000000000000000000000000000;
    call identity;  // IDENTITY
    dw 0x0500000000000000000000000000000000000000;
    call modexp;  // MODEXP
    dw 0x0600000000000000000000000000000000000000;
    call alt_bn128_add;  // ECADD
    dw 0x0700000000000000000000000000000000000000;
    call alt_bn128_mul;  // ECMUL
    dw 0x0800000000000000000000000000000000000000;
    call alt_bn128_pairing_check;  // ECPAIRING
    dw 0x0900000000000000000000000000000000000000;
    call blake2f;  // BLAKE2F
    dw 0x0a00000000000000000000000000000000000000;
    call point_evaluation;  // POINT_EVALUATION
    dw 0x0b00000000000000000000000000000000000000;
    call bls12_g1_add;  // BLS12_G1ADD
    dw 0x0c00000000000000000000000000000000000000;
    call bls12_g1_msm;  // BLS12_G1MSM
    dw 0x0d00000000000000000000000000000000000000;
    call bls12_g2_add;  // BLS12_G2ADD
    dw 0x0e00000000000000000000000000000000000000;
    call bls12_g2_msm;  // BLS12_G2MSM
    dw 0x0f00000000000000000000000000000000000000;
    call bls12_pairing;  // BLS12_PAIRING_CHECK
    dw 0x1000000000000000000000000000000000000000;
    call bls12_map_fp_to_g1;  // BLS12_MAP_FP_TO_G1
    dw 0x1100000000000000000000000000000000000000;
    call bls12_map_fp2_to_g2;  // BLS12_MAP_FP2_TO_G2
    // not reached.
    ret;
}

func invalid_precompile() {
    with_attr error_message("InvalidPrecompile") {
        jmp raise.raise_label;
    }
}

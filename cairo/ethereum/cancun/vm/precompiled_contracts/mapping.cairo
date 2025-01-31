from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin, PoseidonBuiltin
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.common.math_cmp import is_le_felt
from starkware.cairo.common.math import split_felt
from ethereum.cancun.vm import Evm
from ethereum.utils.numeric import divmod
from ethereum.cancun.vm.precompiled_contracts.identity import identity
from ethereum.cancun.vm.precompiled_contracts.sha256 import sha256

// currently 10 precompiles.
const N_PRECOMPILES = 10;
const HIGHEST_PRECOMPILE_LEADING_BYTE = 0x0a;

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
    // Addresses are little-endian, we want easy comparison to 0x1-0xa value, take the leading byte
    let (address_high, address_low) = split_felt(address);
    if (address_low != 0) {
        return (0, 0);
    }
    let (leading_byte, _) = divmod(address_high, 2 ** (3 * 8));
    if (leading_byte == 0) {
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
    // - get the fn ptr relative to the current isntruction (precompiled_contracts_location[index + 2])
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
    dw 0x100000000000000000000000000000000000000;
    call invalid_precompile;  // ECRECOVER
    dw 0x200000000000000000000000000000000000000;
    call sha256;  // SHA256
    dw 0x300000000000000000000000000000000000000;
    call invalid_precompile;  // RIPEMD160
    dw 0x400000000000000000000000000000000000000;
    call identity;  // IDENTITY
    dw 0x500000000000000000000000000000000000000;
    call invalid_precompile;  // MODEXP
    dw 0x600000000000000000000000000000000000000;
    call invalid_precompile;  // ECADD
    dw 0x700000000000000000000000000000000000000;
    call invalid_precompile;  // ECMUL
    dw 0x800000000000000000000000000000000000000;
    call invalid_precompile;  // ECPAIRING
    dw 0x900000000000000000000000000000000000000;
    call invalid_precompile;  // BLAKE2F
    dw 0xa00000000000000000000000000000000000000;
    call invalid_precompile;  // POINT_EVALUATION
    // not reached.
    ret;
}

func invalid_precompile() {
    with_attr error_message("invalid_precompile") {
        assert 0 = 1;
    }
    return ();
}

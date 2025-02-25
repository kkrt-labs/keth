from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    KeccakBuiltin,
    ModBuiltin,
    PoseidonBuiltin,
)
from starkware.cairo.common.math_cmp import is_le_felt
from ethereum.cancun.vm.evm_impl import Evm, EvmImpl
from ethereum.exceptions import EthereumException
from ethereum.cancun.vm.exceptions import KZGProofError
from ethereum.cancun.vm.gas import charge_gas, GasConstants
from ethereum_types.numeric import Uint, U256, U256Struct
from ethereum_types.bytes import Bytes, Bytes32, BytesStruct
from ethereum.cancun.vm.memory import buffer_read

// Constants for the point evaluation precompile
const FIELD_ELEMENTS_PER_BLOB = 4096;
const BLS_MODULUS = 52435875175126190479447740508185965837690552500527637822603658699938581184513;

func point_evaluation{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    let data = evm.value.message.value.data;

    // Check data length
    if (data.value.len != 192) {
        tempvar err = new EthereumException(KZGProofError);
        return err;
    }

    // Charge gas
    let err = charge_gas(Uint(GasConstants.GAS_POINT_EVALUATION));
    if (cast(err, felt) != 0) {
        return err;
    }

    // Extract components from data
    tempvar u256_zero = U256(new U256Struct(0, 0));
    tempvar u256_thirty_two = U256(new U256Struct(32, 0));
    tempvar u256_sixty_four = U256(new U256Struct(64, 0));
    tempvar u256_ninety_six = U256(new U256Struct(96, 0));
    tempvar u256_one_forty_four = U256(new U256Struct(144, 0));

    let versioned_hash_bytes = buffer_read(data, u256_zero, u256_thirty_two);
    let z_bytes = buffer_read(data, u256_thirty_two, u256_thirty_two);
    let y_bytes = buffer_read(data, u256_sixty_four, u256_thirty_two);
    let commitment_bytes = buffer_read(data, u256_ninety_six, u256_thirty_two);
    let proof_bytes = buffer_read(data, u256_one_forty_four, u256_thirty_two);

    // Prepare for hint execution
    tempvar versioned_hash_bytes = versioned_hash_bytes;
    tempvar z_bytes = z_bytes;
    tempvar y_bytes = y_bytes;
    tempvar commitment_bytes = commitment_bytes;
    tempvar proof_bytes = proof_bytes;
    tempvar data = data;

    tempvar error: EthereumException*;
    tempvar output: Bytes;

    %{ point_evaluation_hint %}

    if (cast(error, felt) != 0) {
        return error;
    }

    EvmImpl.set_output(output);
    tempvar ok = cast(0, EthereumException*);
    return ok;
}

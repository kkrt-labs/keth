from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    KeccakBuiltin,
    ModBuiltin,
    PoseidonBuiltin,
)
from starkware.cairo.common.math_cmp import is_le_felt
from ethereum_types.bytes import Bytes, Bytes32, BytesStruct, Bytes48
from ethereum_types.numeric import Uint, U256, U256Struct
from ethereum.cancun.vm.evm_impl import Evm, EvmImpl
from ethereum.cancun.vm.exceptions import KZGProofError
from ethereum.cancun.vm.gas import charge_gas, GasConstants
from ethereum.cancun.vm.memory import buffer_read
from ethereum.crypto.kzg import verify_kzg_proof, kzg_commitment_to_versioned_hash
from ethereum.exceptions import EthereumException
from ethereum.utils.bytes import Bytes32__eq__, Bytes__extend__, Bytes_to_Bytes32, Bytes32_to_Bytes
from ethereum.utils.numeric import U256_to_be_bytes, U384_from_le_bytes

// Constants for the point evaluation precompile
const FIELD_ELEMENTS_PER_BLOB_LOW = 0x1000;
const BLS_MODULUS_LOW = 0x53bda402fffe5bfeffffffff00000001;
const BLS_MODULUS_HIGH = 0x73eda753299d7d483339d80809a1d805;

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

    // Extract components from data
    tempvar u256_zero = U256(new U256Struct(0, 0));
    tempvar u256_thirty_two = U256(new U256Struct(32, 0));
    tempvar u256_forty_eight = U256(new U256Struct(48, 0));
    tempvar u256_sixty_four = U256(new U256Struct(64, 0));
    tempvar u256_ninety_six = U256(new U256Struct(96, 0));
    tempvar u256_one_forty_four = U256(new U256Struct(144, 0));

    let versioned_hash_bytes = buffer_read(data, u256_zero, u256_thirty_two);
    let z_bytes = buffer_read(data, u256_thirty_two, u256_thirty_two);
    let y_bytes = buffer_read(data, u256_sixty_four, u256_thirty_two);
    let commitment_bytes = buffer_read(data, u256_ninety_six, u256_forty_eight);
    let proof_bytes = buffer_read(data, u256_one_forty_four, u256_forty_eight);

    let versioned_hash_bytes32 = Bytes_to_Bytes32(versioned_hash_bytes);
    let z_bytes32 = Bytes_to_Bytes32(z_bytes);
    let y_bytes32 = Bytes_to_Bytes32(y_bytes);

    let commitment_u384 = U384_from_le_bytes(commitment_bytes);
    let commitment_bytes48 = Bytes48(commitment_u384.value);
    let proof_u384 = U384_from_le_bytes(proof_bytes);
    let proof_bytes48 = Bytes48(proof_u384.value);

    // GAS
    let err = charge_gas(Uint(GasConstants.GAS_POINT_EVALUATION));
    if (cast(err, felt) != 0) {
        return err;
    }
    let versioned_hash = kzg_commitment_to_versioned_hash(commitment_bytes48);
    let is_versioned_hash_equal = Bytes32__eq__(versioned_hash, versioned_hash_bytes32);
    if (is_versioned_hash_equal.value == 0) {
        tempvar err = new EthereumException(KZGProofError);
        return err;
    }
    let (result, err) = verify_kzg_proof(commitment_bytes48, z_bytes32, y_bytes32, proof_bytes48);
    if (cast(err, felt) != 0) {
        tempvar err = new EthereumException(KZGProofError);
        return err;
    }
    if (result.value == 0) {
        tempvar err = new EthereumException(KZGProofError);
        return err;
    }

    tempvar field_element_per_blob = U256(new U256Struct(FIELD_ELEMENTS_PER_BLOB_LOW, 0));
    tempvar bls_modulus = U256(new U256Struct(BLS_MODULUS_LOW, BLS_MODULUS_HIGH));

    let bls_modulus_bytes_bytes_32 = U256_to_be_bytes(bls_modulus);
    let bls_modulus_bytes = Bytes32_to_Bytes(bls_modulus_bytes_bytes_32);
    let output_bytes_32 = U256_to_be_bytes(field_element_per_blob);
    let output = Bytes32_to_Bytes(output_bytes_32);
    Bytes__extend__{self=output}(bls_modulus_bytes);

    EvmImpl.set_output(output);
    tempvar ok = cast(0, EthereumException*);
    return ok;
}

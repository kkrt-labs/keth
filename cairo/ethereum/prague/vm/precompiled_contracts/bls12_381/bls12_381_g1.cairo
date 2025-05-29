//! Important: the implementations of these precompiles is unsound.
//! TODO: Add rust implementations for the hints.

from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, ModBuiltin, PoseidonBuiltin
from ethereum.prague.vm.evm_impl import Evm, EvmImpl
from ethereum.exceptions import EthereumException
from ethereum.prague.vm.exceptions import InvalidParameter
from ethereum.utils.numeric import divmod
from ethereum.prague.vm.gas import GasConstants, charge_gas
from ethereum_types.numeric import Uint
from ethereum_types.bytes import Bytes
from cairo_core.comparison import is_zero, is_not_zero

// @notice The bls12_381 G1 point addition precompile.
// @dev The implementation is unsound.
func bls12_g1_add{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    let data = evm.value.message.value.data;

    if (data.value.len != 256) {
        tempvar err = new EthereumException(InvalidParameter);
        return err;
    }

    // gas
    let err = charge_gas(Uint(GasConstants.GAS_BLS_G1_ADD));
    if (cast(err, felt) != 0) {
        return err;
    }
    // Operation
    tempvar data = data;
    tempvar error: EthereumException*;
    tempvar output: Bytes;
    %{ bls12_g1_add_hint %}
    if (cast(error, felt) != 0) {
        return error;
    }

    EvmImpl.set_output(output);
    tempvar ok = cast(0, EthereumException*);
    return ok;
}

// @notice The bls12_381 G1 multi-scalar multiplication precompile.
// @dev The implementation is unsound.
func bls12_g1_msm{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;

    let data = evm.value.message.value.data;
    let (q, r) = divmod(data.value.len, 160);
    let data_multiple_of_160 = is_not_zero(r);
    let data_is_zero = is_zero(data.value.len);
    let invalid_valid_input = data_multiple_of_160 + data_is_zero;

    if (invalid_valid_input != 0) {
        tempvar err = new EthereumException(InvalidParameter);
        return err;
    }

    tempvar data = data;
    tempvar gas;
    %{ bls12_g1_msm_gas_hint %}
    let err = charge_gas(Uint(gas));
    if (cast(err, felt) != 0) {
        return err;
    }

    tempvar data = evm.value.message.value.data;
    tempvar error: EthereumException*;
    tempvar output: Bytes;

    %{ bls12_g1_msm_hint %}
    if (cast(error, felt) != 0) {
        return error;
    }

    EvmImpl.set_output(output);
    tempvar ok = cast(0, EthereumException*);
    return ok;
}

// @notice Precompile to map field element to G1.
// @dev The implementation is unsound.
func bls12_map_fp_to_g1{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;

    let data = evm.value.message.value.data;
    if (data.value.len != 64) {
        tempvar err = new EthereumException(InvalidParameter);
        return err;
    }

    // gas
    let err = charge_gas(Uint(GasConstants.GAS_BLS_G1_MAP));
    if (cast(err, felt) != 0) {
        return err;
    }

    // operation
    tempvar data = data;
    tempvar error: EthereumException*;
    tempvar output: Bytes;

    %{ bls12_map_fp_to_g1_hint %}
    if (cast(error, felt) != 0) {
        return error;
    }

    EvmImpl.set_output(output);
    tempvar ok = cast(0, EthereumException*);
    return ok;
}

from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    ModBuiltin,
    PoseidonBuiltin,
)
from ethereum.prague.vm.evm_impl import Evm, EvmImpl
from ethereum.exceptions import EthereumException
from ethereum.prague.vm.exceptions import OutOfGasError, InvalidParameter
from ethereum.utils.numeric import ceil32, divmod, U256_from_be_bytes
from ethereum.prague.vm.gas import GasConstants, charge_gas
from ethereum_types.numeric import Uint
from ethereum_types.bytes import Bytes

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

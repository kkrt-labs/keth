//! Important: the implementations of these precompiles is unsound.

from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, ModBuiltin, PoseidonBuiltin
from ethereum.prague.vm.evm_impl import Evm, EvmImpl
from ethereum.exceptions import EthereumException
from ethereum.prague.vm.exceptions import InvalidParameter
from ethereum.utils.numeric import divmod
from ethereum.prague.vm.gas import charge_gas
from ethereum_types.numeric import Uint
from ethereum_types.bytes import Bytes
from cairo_core.comparison import is_zero, is_not_zero

// @notice The bls12_381 pairing precompile.
// @dev The implementation is unsound.
func bls12_pairing{
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
    let (q, r) = divmod(data.value.len, 384);
    let data_multiple_of_384 = is_not_zero(r);
    let data_is_zero = is_zero(data.value.len);
    let invalid_valid_input = data_multiple_of_384 + data_is_zero;

    if (invalid_valid_input != 0) {
        tempvar err = new EthereumException(InvalidParameter);
        return err;
    }

    // GAS
    let gas_cost = Uint(32600 * q + 37700);
    let err = charge_gas(gas_cost);
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    tempvar data = evm.value.message.value.data;
    tempvar error: EthereumException*;
    tempvar output: Bytes;

    %{ bls12_pairing_hint %}
    if (cast(error, felt) != 0) {
        return error;
    }

    EvmImpl.set_output(output);
    tempvar ok = cast(0, EthereumException*);
    return ok;
}

from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.math_cmp import is_le_felt
from ethereum.cancun.vm import Evm, EvmImpl
from ethereum.exceptions import EthereumException
from ethereum.cancun.vm.exceptions import OutOfGasError
from ethereum.utils.numeric import ceil32, divmod
from ethereum.cancun.vm.gas import GasConstants, charge_gas
from ethereum_types.numeric import Uint
from ethereum_types.bytes import Bytes

// @notice Writes the message data to the output
func alt_bn128_pairing_check{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*, evm: Evm
}() -> EthereumException* {
    alloc_locals;
    let data = evm.value.message.value.data;

    // Gas
    let (data_factor, rem) = divmod(data.value.len, 192);
    let gas_cost = Uint(34000 * data_factor + 45000);
    let err = charge_gas(gas_cost);
    if (cast(err, felt) != 0) {
        return err;
    }

    // Operation
    if (rem != 0) {
        tempvar err = new EthereumException(OutOfGasError);
        return err;
    }

    tempvar data = data;
    tempvar error: EthereumException*;
    tempvar output: Bytes;
    %{ alt_bn128_pairing_check_hint %}

    if (cast(error, felt) != 0) {
        return error;
    }

    EvmImpl.set_output(output);
    tempvar ok = cast(0, EthereumException*);
    return ok;
}

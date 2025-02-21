from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.math_cmp import is_le_felt
from ethereum.cancun.vm import Evm, EvmImpl
from ethereum.exceptions import EthereumException
from ethereum.cancun.vm.exceptions import OutOfGasError
from ethereum.utils.numeric import ceil32, divmod, U256_from_be_bytes
from ethereum.cancun.vm.gas import GasConstants, charge_gas
from ethereum_types.numeric import Uint, U256, U256Struct
from ethereum_types.bytes import Bytes
from ethereum.cancun.vm.memory import buffer_read

func alt_bn128_add{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*, evm: Evm}() -> EthereumException* {
    alloc_locals;
    let data = evm.value.message.value.data;

    // Gas
    let err = charge_gas(Uint(150));
    if (cast(err, felt) != 0) {
        return err;
    }

    // Operation
    tempvar u256_zero = U256(new U256Struct(0, 0));
    tempvar u256_thirty_two = U256(new U256Struct(32, 0));
    tempvar u256_sixty_four = U256(new U256Struct(64, 0));
    tempvar u256_ninety_six = U256(new U256Struct(96, 0));
    let x0_bytes = buffer_read(data, u256_zero, u256_thirty_two);
    let y0_bytes = buffer_read(data, u256_thirty_two, u256_thirty_two);
    let x1_bytes = buffer_read(data, u256_sixty_four, u256_thirty_two);
    let y1_bytes = buffer_read(data, u256_ninety_six, u256_thirty_two);

    let x0_value = U256_from_be_bytes(x0_bytes);
    let y0_value = U256_from_be_bytes(y0_bytes);
    let x1_value = U256_from_be_bytes(x1_bytes);
    let y1_value = U256_from_be_bytes(y1_bytes);

    tempvar x0_value = x0_value;
    tempvar y0_value = y0_value;
    tempvar x1_value = x1_value;
    tempvar y1_value = y1_value;

    tempvar error: EthereumException*;
    tempvar output: Bytes;

    %{ alt_bn128_add_hint %}
    if (cast(error, felt) != 0) {
        return error;
    }

    EvmImpl.set_output(output);
    tempvar ok = cast(0, EthereumException*);
    return ok;
}


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

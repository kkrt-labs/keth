from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, PoseidonBuiltin, ModBuiltin
from starkware.cairo.common.registers import get_label_location

from ethereum.cancun.vm.instructions.system import (
    generic_create,
    generic_call,
    create,
    create2,
    call_,
    callcode,
    delegatecall,
    staticcall,
)
from ethereum.cancun.vm.interpreter import process_create_message, process_message
from ethereum_types.numeric import U256, Uint, bool
from ethereum.cancun.fork_types import Address
from ethereum.exceptions import EthereumException
from ethereum.cancun.vm.evm_impl import Evm

func test_generic_create{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}(
    endowment: U256,
    contract_address: Address,
    memory_start_position: U256,
    memory_size: U256,
) -> EthereumException* {
    let (process_create_message_label) = get_label_location(process_create_message);
    let res = generic_create{process_create_message_label=process_create_message_label, evm=evm}(
        endowment, contract_address, memory_start_position, memory_size
    );
    return res;
}

func test_create{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let (process_create_message_label) = get_label_location(process_create_message);
    let (process_message_label) = get_label_location(process_message);
    let res = create{
        process_create_message_label=process_create_message_label,
        process_message_label=process_message_label,
    }();
    return res;
}

func test_create2{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let (process_create_message_label) = get_label_location(process_create_message);
    let (process_message_label) = get_label_location(process_message);
    let res = create2{
        process_create_message_label=process_create_message_label,
        process_message_label=process_message_label,
    }();
    return res;
}

func test_generic_call{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}(
    gas: Uint,
    value: U256,
    caller: Address,
    to: Address,
    code_address: Address,
    should_transfer_value: bool,
    is_staticcall: bool,
    memory_input_start_position: U256,
    memory_input_size: U256,
    memory_output_start: U256,
    memory_output_size: U256,
) -> EthereumException* {
    let (process_message_label) = get_label_location(process_message);
    let res = generic_call{process_message_label=process_message_label, evm=evm}(
        gas,
        value,
        caller,
        to,
        code_address,
        should_transfer_value,
        is_staticcall,
        memory_input_start_position,
        memory_input_size,
        memory_output_start,
        memory_output_size,
    );
    return res;
}

func test_call{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let (process_message_label) = get_label_location(process_message);
    let result = call_{process_message_label=process_message_label, evm=evm}();
    return result;
}

func test_callcode{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let (process_message_label) = get_label_location(process_message);
    let res = callcode{process_message_label=process_message_label, evm=evm}();
    return res;
}

func test_delegatecall{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let (process_message_label) = get_label_location(process_message);
    let res = delegatecall{process_message_label=process_message_label, evm=evm}();
    return res;
}

func test_staticcall{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let (process_message_label) = get_label_location(process_message);
    let res = staticcall{process_message_label=process_message_label, evm=evm}();
    return res;
}

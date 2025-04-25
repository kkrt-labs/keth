from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, PoseidonBuiltin, ModBuiltin
from starkware.cairo.common.registers import get_label_location

from ethereum.cancun.vm.instructions import op_implementation
from ethereum.cancun.vm.interpreter import process_create_message, process_message
from ethereum.cancun.vm.exceptions import EthereumException
from ethereum.cancun.vm.evm_impl import Evm

func test_op_implementation{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}(opcode: felt) -> EthereumException* {
    let (process_create_message_label) = get_label_location(process_create_message);
    let (process_message_label) = get_label_location(process_message);
    let res = op_implementation(process_create_message_label, process_message_label, opcode);
    return res;
}

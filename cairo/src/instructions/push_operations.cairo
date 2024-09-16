from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.math_cmp import is_nn

from src.constants import Constants
from src.errors import Errors
from src.evm import EVM
from src.model import model
from src.stack import Stack
from src.state import State
from src.utils.utils import Helpers

// @title Push operations opcodes.
namespace PushOperations {
    func exec_push{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        stack: model.Stack*,
        memory: model.Memory*,
        state: model.State*,
    }(evm: model.EVM*) -> model.EVM* {
        alloc_locals;

        let opcode_number = [evm.message.bytecode + evm.program_counter];
        let i = opcode_number - 0x5f;

        // Copy code slice
        let pc = evm.program_counter + 1;
        let out_of_bounds = is_nn(pc + i - evm.message.bytecode_len);
        local len = (1 - out_of_bounds) * i + out_of_bounds * (evm.message.bytecode_len - pc);

        let stack_element = Helpers.bytes_to_uint256(len, evm.message.bytecode + pc);
        Stack.push_uint256(stack_element);

        let evm = EVM.increment_program_counter(evm, len);

        return evm;
    }
}

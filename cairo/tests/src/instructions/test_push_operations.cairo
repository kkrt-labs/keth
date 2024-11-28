from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.memset import memset
from starkware.cairo.common.memcpy import memcpy

from src.utils.utils import Helpers
from src.model import model
from src.stack import Stack
from src.state import State
from src.memory import Memory
from src.instructions.push_operations import PushOperations
from tests.utils.helpers import TestHelpers

func test__exec_push{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}() -> model.Stack* {
    alloc_locals;
    local i: felt;
    %{ ids.i = program_input["i"] %}

    let (bytecode) = alloc();
    assert [bytecode] = i + 0x5f;
    memset(bytecode + 1, 0xff, i);
    let stack = Stack.init();
    let memory = Memory.init();
    let state = State.init();
    let evm = TestHelpers.init_evm_with_bytecode(1 + i, bytecode);

    with stack, memory, state {
        let evm = PushOperations.exec_push(evm);
    }

    return stack;
}

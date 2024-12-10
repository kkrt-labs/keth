from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.memcpy import memcpy

from src.stack import Stack
from src.memory import Memory
from src.state import State
from src.model import model
from src.instructions.exchange_operations import ExchangeOperations
from tests.utils.helpers import TestHelpers

func test__exec_swap{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}() -> model.Stack* {
    alloc_locals;

    local i: felt;
    local initial_stack_len: felt;
    let (initial_stack_ptr: felt*) = alloc();
    let initial_stack = cast(initial_stack_ptr, Uint256*);
    %{
        from itertools import chain
        ids.i = program_input["i"]
        ids.initial_stack_len = len(program_input["initial_stack"])
        segments.write_arg(ids.initial_stack_ptr, list(chain(*program_input["initial_stack"])))
    %}

    let stack = TestHelpers.init_stack_with_values(initial_stack_len, initial_stack);
    let memory = Memory.init();
    let state = State.init();
    let initial_state = State.copy{state=state}();
    let (bytecode) = alloc();
    assert [bytecode] = i + 0x8f;
    let evm = TestHelpers.init_evm_with_bytecode{initial_state=initial_state}(1, bytecode);

    // When
    with stack, memory, state {
        let evm = ExchangeOperations.exec_swap(evm);
        let (top) = Stack.peek(0);
        let (swapped) = Stack.peek(i);
    }

    return stack;
}

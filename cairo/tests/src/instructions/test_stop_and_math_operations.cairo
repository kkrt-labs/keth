from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import TRUE
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.uint256 import Uint256

from src.stack import Stack
from src.state import State
from src.memory import Memory
from src.model import model
from src.instructions.stop_and_math_operations import StopAndMathOperations
from tests.utils.helpers import TestHelpers

func test__exec_stop{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}() {
    alloc_locals;

    let stack = Stack.init();
    let memory = Memory.init();
    let state = State.init();
    let initial_state = State.copy{state=state}();
    let evm = TestHelpers.init_evm{initial_state=initial_state}();

    with stack, memory, state {
        let evm = StopAndMathOperations.exec_stop(evm);
    }

    assert evm.stopped = TRUE;
    assert evm.return_data_len = 0;

    return ();
}

func test__exec_math_operation{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}() -> (evm: model.EVM*, result: Uint256*) {
    // Given
    alloc_locals;

    tempvar opcode;
    tempvar initial_stack_len: felt;
    let (initial_stack: felt*) = alloc();
    %{
        ids.opcode = program_input["opcode"];
        ids.initial_stack_len = len(program_input["stack"]);
        segments.write_arg(ids.initial_stack, program_input["stack"])
    %}

    let (bytecode) = alloc();
    assert [bytecode] = opcode;
    let memory = Memory.init();
    let stack = TestHelpers.init_stack_with_values(
        initial_stack_len, cast(initial_stack, Uint256*)
    );
    let state = State.init();
    let initial_state = State.copy{state=state}();
    let evm = TestHelpers.init_evm_with_bytecode{initial_state=initial_state}(1, bytecode);

    // When
    with stack, memory, state {
        let evm = StopAndMathOperations.exec_math_operation(evm);
        let (result) = Stack.peek(0);
    }

    // Then
    return (evm, result);
}

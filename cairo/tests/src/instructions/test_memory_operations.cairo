from ethereum_types.numeric import U256
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.uint256 import Uint256, assert_uint256_eq
from src.account import Account
from src.model import model
from src.stack import Stack
from src.state import State
from src.memory import Memory
from src.evm import EVM
from src.instructions.memory_operations import MemoryOperations
from tests.utils.helpers import TestHelpers

func test__exec_pc__should_return_evm_program_counter{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}() {
    // Given
    alloc_locals;

    local increment: felt;
    %{ ids.increment = program_input["increment"] %}

    let stack = Stack.init();
    let memory = Memory.init();
    let state = State.init();
    let initial_state = State.copy{state=state}();
    let (bytecode) = alloc();
    let evm = TestHelpers.init_evm_with_bytecode(initial_state, 0, bytecode);
    let evm = EVM.increment_program_counter(evm, increment);

    // When
    with stack, memory, state {
        let evm = MemoryOperations.exec_pc(evm);
        let (index0) = Stack.peek(0);
    }

    // Then
    assert stack.size = 1;
    assert index0.low = increment;
    assert index0.high = 0;
    return ();
}

func test__exec_pop_should_pop_an_item_from_execution_context{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}() {
    // Given
    alloc_locals;
    let stack = Stack.init();
    let memory = Memory.init();
    let state = State.init();
    let initial_state = State.copy{state=state}();
    let (bytecode) = alloc();
    let evm = TestHelpers.init_evm_with_bytecode(initial_state, 0, bytecode);

    tempvar item_1 = new Uint256(1, 0);
    tempvar item_0 = new Uint256(2, 0);

    // When
    with stack, memory, state {
        Stack.push(item_1);
        Stack.push(item_0);

        let evm = MemoryOperations.exec_pop(evm);
        let (index0) = Stack.peek(0);
    }

    // Then
    assert stack.size = 1;
    assert_uint256_eq([index0], Uint256(1, 0));
    return ();
}

func test__exec_mload_should_load_a_value_from_memory{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}() {
    // Given
    alloc_locals;
    let stack = Stack.init();
    let memory = Memory.init();
    let state = State.init();
    let initial_state = State.copy{state=state}();
    let (bytecode) = alloc();
    let evm = TestHelpers.init_evm_with_bytecode(initial_state, 0, bytecode);

    tempvar item_1 = new Uint256(1, 0);
    tempvar item_0 = new Uint256(0, 0);

    // When
    with stack, memory, state {
        Stack.push(item_1);
        Stack.push(item_0);

        let evm = MemoryOperations.exec_mstore(evm);

        Stack.push(item_0);

        let evm = MemoryOperations.exec_mload(evm);
        let (index0) = Stack.peek(0);
    }

    // Then
    assert stack.size = 1;
    assert_uint256_eq([index0], [item_1]);
    return ();
}

func test__exec_mload_should_load_a_value_from_memory_with_memory_expansion{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}() {
    // Given
    alloc_locals;
    let stack = Stack.init();
    let memory = Memory.init();
    let state = State.init();
    let initial_state = State.copy{state=state}();
    let (bytecode) = alloc();
    let evm = TestHelpers.init_evm_with_bytecode(initial_state, 0, bytecode);

    with stack, memory, state {
        tempvar item_1 = new Uint256(1, 0);
        tempvar item_0 = new Uint256(0, 0);

        Stack.push(item_1);
        Stack.push(item_0);

        let evm = MemoryOperations.exec_mstore(evm);

        tempvar offset = new Uint256(16, 0);
        Stack.push(offset);

        let evm = MemoryOperations.exec_mload(evm);
        let (index0) = Stack.peek(0);
    }

    assert stack.size = 1;
    assert_uint256_eq([index0], Uint256(0, 1));
    assert memory.words_len = 2;
    return ();
}

func test__exec_mload_should_load_a_value_from_memory_with_offset_larger_than_msize{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}() {
    // Given
    alloc_locals;
    let test_offset = 684;
    let stack = Stack.init();
    let memory = Memory.init();
    let state = State.init();
    let initial_state = State.copy{state=state}();
    let (bytecode) = alloc();
    let evm = TestHelpers.init_evm_with_bytecode(initial_state, 0, bytecode);

    tempvar item_1 = new Uint256(1, 0);
    tempvar item_0 = new Uint256(0, 0);

    with stack, memory, state {
        Stack.push(item_1);
        Stack.push(item_0);

        let evm = MemoryOperations.exec_mstore(evm);
        tempvar offset = new Uint256(test_offset, 0);
        Stack.push(offset);

        let evm = MemoryOperations.exec_mload(evm);

        let (index0) = Stack.peek(0);
    }
    assert stack.size = 1;
    assert_uint256_eq([index0], Uint256(0, 0));
    assert memory.words_len = 23;
    return ();
}

func test__exec_mcopy{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}() -> (model.EVM*, model.Memory*) {
    alloc_locals;
    let (memory_init_state) = alloc();
    local memory_init_state_len: felt;
    let (size_mcopy_ptr) = alloc();
    let (src_offset_mcopy_ptr) = alloc();
    let (dst_offset_mcopy_ptr) = alloc();

    %{
        ids.memory_init_state_len = len(program_input["memory_init_state"])
        segments.write_arg(ids.memory_init_state, program_input["memory_init_state"])
        segments.write_arg(ids.size_mcopy_ptr, program_input["size_mcopy"])
        segments.write_arg(ids.src_offset_mcopy_ptr, program_input["src_offset_mcopy"])
        segments.write_arg(ids.dst_offset_mcopy_ptr, program_input["dst_offset_mcopy"])
    %}

    let size_mcopy = cast(size_mcopy_ptr, Uint256*);
    let src_offset_mcopy = cast(src_offset_mcopy_ptr, Uint256*);
    let dst_offset_mcopy = cast(dst_offset_mcopy_ptr, Uint256*);

    let stack = Stack.init();
    let memory = TestHelpers.init_memory_with_values(memory_init_state_len, memory_init_state);
    let state = State.init();
    let initial_state = State.copy{state=state}();
    let evm = TestHelpers.init_evm(initial_state);

    with stack, memory, state {
        Stack.push(size_mcopy);
        Stack.push(src_offset_mcopy);
        Stack.push(dst_offset_mcopy);
        let evm = MemoryOperations.exec_mcopy(evm);
    }
    return (evm, memory);
}

func test_exec_mstore{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}() -> (model.EVM*, model.Memory*) {
    alloc_locals;
    let (value_ptr) = alloc();
    let (offset_ptr) = alloc();

    %{
        segments.write_arg(ids.value_ptr, program_input["value"])
        segments.write_arg(ids.offset_ptr, program_input["offset"])
    %}

    let stack = Stack.init();
    let memory = Memory.init();
    let state = State.init();
    let initial_state = State.copy{state=state}();
    let evm = TestHelpers.init_evm(initial_state);

    let value = cast(value_ptr, Uint256*);
    let offset = cast(offset_ptr, Uint256*);

    with stack, memory, state {
        Stack.push(value);
        Stack.push(offset);

        let evm = MemoryOperations.exec_mstore(evm);
    }
    return (evm, memory);
}

func test_exec_sstore{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}(initial_value: U256, new_value: U256, key: U256, address: felt) -> model.State* {
    alloc_locals;

    let (local code: felt*) = alloc();
    tempvar code_hash = new Uint256(0, 0);
    tempvar balance = new Uint256(0, 0);
    let account = Account.init(0, code, code_hash, 0, balance);

    let stack = Stack.init();
    let memory = Memory.init();
    let state = State.init();
    with state {
        State.update_account(address, account);
        State.write_storage(address, key.value, initial_value.value);
    }
    let initial_state = State.copy{state=state}();
    let (bytecode) = alloc();
    let (calldata) = alloc();
    let evm = TestHelpers.init_evm_at_address(initial_state, 0, bytecode, address, 0, calldata);

    with stack, memory, state {
        Stack.push(new_value.value);
        Stack.push(key.value);
        let evm = MemoryOperations.exec_sstore(evm);
    }
    return state;
}

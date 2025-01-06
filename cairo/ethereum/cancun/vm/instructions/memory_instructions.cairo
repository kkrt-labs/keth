from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.uint256 import uint256_eq, Uint256, uint256_and
from starkware.cairo.common.math_cmp import is_le_felt

from ethereum.cancun.vm.stack import Stack, pop, push
from ethereum.cancun.vm import Evm, EvmImpl, EvmStruct
from ethereum.cancun.vm.exceptions import ExceptionalHalt, OutOfGasError
from ethereum_types.numeric import U256, U256Struct, Uint
from ethereum.cancun.vm.gas import (
    charge_gas,
    GasConstants,
    ExtendMemory,
    calculate_gas_extend_memory,
)
from ethereum.cancun.vm.memory import Memory, memory_read_bytes, memory_write, expand_by
from ethereum.utils.numeric import ceil32, divmod
from ethereum_types.bytes import Bytes, BytesStruct
from starkware.cairo.common.alloc import alloc
from ethereum_types.others import (
    ListTupleU256U256,
    ListTupleU256U256Struct,
    TupleU256U256,
    TupleU256U256Struct,
)
from src.utils.bytes import uint256_to_bytes32
from src.utils.utils import Helpers

// @notice Stores a word to memory
func mstore{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (start_position, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (value, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // GAS
    tempvar mem_access_tuple = new TupleU256U256(
        new TupleU256U256Struct(start_position, U256(new U256Struct(32, 0)))
    );
    tempvar mem_access_list = ListTupleU256U256(new ListTupleU256U256Struct(mem_access_tuple, 1));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, mem_access_list);

    // assumed that cost < 2**110 (see calculate_memory_gas_cost)
    let err = charge_gas(Uint(GasConstants.GAS_VERY_LOW + extend_memory.value.cost.value));
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    let memory = evm.value.memory;
    let (value_data: felt*) = alloc();
    uint256_to_bytes32(value_data, [value.value]);
    tempvar value_bytes = Bytes(new BytesStruct(value_data, 32));

    let memory = evm.value.memory;
    with memory {
        expand_by(extend_memory.value.expand_by);
        memory_write(start_position, value_bytes);
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack_memory(Uint(evm.value.pc.value + 1), stack, memory);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Stores a byte to memory
func mstore8{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (start_position, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (value, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // GAS
    tempvar mem_access_tuple = new TupleU256U256(
        new TupleU256U256Struct(start_position, U256(new U256Struct(1, 0)))
    );
    tempvar mem_access_list = ListTupleU256U256(new ListTupleU256U256Struct(mem_access_tuple, 1));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, mem_access_list);

    // assumed that cost < 2**110 (see calculate_memory_gas_cost)
    let err = charge_gas(Uint(GasConstants.GAS_VERY_LOW + extend_memory.value.cost.value));
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    let (data) = alloc();
    assert bitwise_ptr.x = value.value.low;
    assert bitwise_ptr.y = 0xFF;
    assert [data] = bitwise_ptr.x_and_y;
    let bitwise_ptr = bitwise_ptr + BitwiseBuiltin.SIZE;
    tempvar value_bytes = Bytes(new BytesStruct(data, 1));

    let memory = evm.value.memory;
    with memory {
        expand_by(extend_memory.value.expand_by);
        memory_write(start_position, value_bytes);
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack_memory(Uint(evm.value.pc.value + 1), stack, memory);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Load word from memory
func mload{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (start_position, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // GAS
    tempvar mem_access_tuple = new TupleU256U256(
        new TupleU256U256Struct(start_position, U256(new U256Struct(32, 0)))
    );
    tempvar mem_access_list = ListTupleU256U256(new ListTupleU256U256Struct(mem_access_tuple, 1));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, mem_access_list);

    // assumed that cost < 2**110 (see calculate_memory_gas_cost)
    let err = charge_gas(Uint(GasConstants.GAS_VERY_LOW + extend_memory.value.cost.value));
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    let memory = evm.value.memory;
    with memory {
        let value_bytes = memory_read_bytes(start_position, U256(new U256Struct(32, 0)));
        expand_by(extend_memory.value.expand_by);
    }
    let value = Helpers.bytes32_to_uint256(value_bytes.value.data);
    with stack {
        let err = push(U256(new U256Struct(value.low, value.high)));
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack_memory(Uint(evm.value.pc.value + 1), stack, memory);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Push the size of active memory in bytes onto the stack
func msize{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK

    // GAS
    let err = charge_gas(Uint(GasConstants.GAS_BASE));
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    let stack = evm.value.stack;
    with stack {
        let err = push(U256(new U256Struct(evm.value.memory.value.len, 0)));
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Copy the bytes in memory from one location to another
func mcopy{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (destination, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (source, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (length, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // GAS
    // OutOfGasError if length > 2**128
    if (length.value.high != 0) {
        tempvar err = new ExceptionalHalt(OutOfGasError);
        return err;
    }

    let length_ceil32 = ceil32(Uint(length.value.low));
    let (words, _) = divmod(length_ceil32.value, 32);
    let copy_gas_cost = GasConstants.GAS_COPY * words;

    let (mem_access_tuples: TupleU256U256*) = alloc();
    assert mem_access_tuples[0] = TupleU256U256(
        new TupleU256U256Struct(source, U256(new U256Struct(length.value.low, 0)))
    );
    assert mem_access_tuples[1] = TupleU256U256(
        new TupleU256U256Struct(destination, U256(new U256Struct(length.value.low, 0)))
    );
    tempvar mem_access_list = ListTupleU256U256(new ListTupleU256U256Struct(mem_access_tuples, 2));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, mem_access_list);

    // copy_gas_cost in [0, 3 * 2**120)
    // extend_memory.value.cost.value in [0, 2**110)
    // -> sum < felt_size, no overflow
    let err = charge_gas(
        Uint(GasConstants.GAS_VERY_LOW + copy_gas_cost + extend_memory.value.cost.value)
    );
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    let memory = evm.value.memory;
    with memory {
        expand_by(extend_memory.value.expand_by);
        let value = memory_read_bytes(source, length);
        memory_write(destination, value);
    }

    EvmImpl.set_pc_stack_memory(Uint(evm.value.pc.value + 1), stack, memory);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

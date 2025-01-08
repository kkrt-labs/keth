from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

from ethereum.cancun.vm.stack import pop
from ethereum.cancun.vm import Evm, EvmImpl
from ethereum.cancun.vm.exceptions import ExceptionalHalt, WriteInStaticContext, OutOfGasError
from ethereum.cancun.vm.memory import memory_read_bytes, expand_by
from ethereum.cancun.vm.gas import calculate_gas_extend_memory, charge_gas, GasConstants
from ethereum.utils.numeric import U256_to_be_bytes
from ethereum_types.numeric import U256, U256Struct, Uint
from ethereum_types.bytes import Bytes, Bytes32, Bytes32Struct, TupleBytes32, TupleBytes32Struct
from ethereum_types.others import (
    ListTupleU256U256,
    ListTupleU256U256Struct,
    TupleU256U256,
    TupleU256U256Struct,
)
from ethereum.cancun.blocks import Log, LogStruct, TupleLog, TupleLogStruct

// @notice LOG0 instruction - append log record with no topics
func log0{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    const NUM_TOPICS = 0;

    // STACK
    let stack = evm.value.stack;
    with stack {
        // Pop memory_start_index and size
        let (memory_start_index, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (size, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // GAS
    // Calculate memory expansion cost
    // If the size is greater than 2**128, the memory expansion will trigger an out of gas error.
    if (size.value.high != 0) {
        tempvar err = new ExceptionalHalt(OutOfGasError);
        return err;
    }

    // Calculate memory expansion cost
    tempvar mem_access_tuple = new TupleU256U256(new TupleU256U256Struct(memory_start_index, size));
    tempvar mem_access_list = ListTupleU256U256(new ListTupleU256U256Struct(mem_access_tuple, 1));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, mem_access_list);

    // Calculate total gas cost
    let data_cost = GasConstants.GAS_LOG_DATA * size.value.low;
    let topic_cost = GasConstants.GAS_LOG_TOPIC * NUM_TOPICS;
    let total_cost = Uint(
        GasConstants.GAS_LOG + data_cost + topic_cost + extend_memory.value.cost.value
    );

    let err = charge_gas(total_cost);
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    let memory = evm.value.memory;
    with memory {
        expand_by(extend_memory.value.expand_by);
        let data = memory_read_bytes(memory_start_index, size);
    }

    // Create log entry
    tempvar topics = TupleBytes32(new TupleBytes32Struct(cast(0, Bytes32*), 0));
    tempvar log_entry = Log(
        new LogStruct(address=evm.value.message.value.current_target, topics=topics, data=data)
    );

    // Check for static context
    if (evm.value.message.value.is_static.value != 0) {
        tempvar err = new ExceptionalHalt(WriteInStaticContext);
        return err;
    }

    // Append log entry
    let logs = evm.value.logs.value;
    assert logs.data[logs.len] = log_entry;
    let len = logs.len + 1;
    EvmImpl.set_logs(TupleLog(new TupleLogStruct(logs.data, len)));

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack_memory(Uint(evm.value.pc.value + 1), stack, memory);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice LOG1 instruction - append log record with one topic
func log1{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    const NUM_TOPICS = 1;

    // STACK
    let stack = evm.value.stack;
    with stack {
        // Pop memory_start_index, size and topic
        let (memory_start_index, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (size, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (topic, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // GAS
    // Calculate memory expansion cost
    // If the size is greater than 2**128, the memory expansion will trigger an out of gas error.
    if (size.value.high != 0) {
        tempvar err = new ExceptionalHalt(OutOfGasError);
        return err;
    }

    // Calculate memory expansion cost
    tempvar mem_access_tuple = new TupleU256U256(new TupleU256U256Struct(memory_start_index, size));
    tempvar mem_access_list = ListTupleU256U256(new ListTupleU256U256Struct(mem_access_tuple, 1));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, mem_access_list);

    // Calculate total gas cost
    let data_cost = GasConstants.GAS_LOG_DATA * size.value.low;
    let topic_cost = GasConstants.GAS_LOG_TOPIC * NUM_TOPICS;
    let total_cost = Uint(
        GasConstants.GAS_LOG + data_cost + topic_cost + extend_memory.value.cost.value
    );

    let err = charge_gas(total_cost);
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    let memory = evm.value.memory;
    with memory {
        expand_by(extend_memory.value.expand_by);
        let data = memory_read_bytes(memory_start_index, size);
    }

    // Create log entry
    let be_topic_ = U256_to_be_bytes(topic);
    tempvar be_topic = new Bytes32(be_topic_.value);
    tempvar topics = TupleBytes32(new TupleBytes32Struct(be_topic, 1));
    tempvar log_entry = Log(
        new LogStruct(address=evm.value.message.value.current_target, topics=topics, data=data)
    );

    // Check for static context
    if (evm.value.message.value.is_static.value != 0) {
        tempvar err = new ExceptionalHalt(WriteInStaticContext);
        return err;
    }

    // Append log entry
    let logs = evm.value.logs.value;
    assert logs.data[logs.len] = log_entry;
    let len = logs.len + 1;
    EvmImpl.set_logs(TupleLog(new TupleLogStruct(logs.data, len)));

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack_memory(Uint(evm.value.pc.value + 1), stack, memory);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice LOG2 instruction - append log record with two topics
func log2{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    const NUM_TOPICS = 2;

    // STACK
    let stack = evm.value.stack;
    with stack {
        // Pop memory_start_index and size
        let (memory_start_index, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (size, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (topic1, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (topic2, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // GAS
    // Calculate memory expansion cost
    // If the size is greater than 2**128, the memory expansion will trigger an out of gas error.
    if (size.value.high != 0) {
        tempvar err = new ExceptionalHalt(OutOfGasError);
        return err;
    }

    // Calculate memory expansion cost
    tempvar mem_access_tuple = new TupleU256U256(new TupleU256U256Struct(memory_start_index, size));
    tempvar mem_access_list = ListTupleU256U256(new ListTupleU256U256Struct(mem_access_tuple, 1));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, mem_access_list);

    // Calculate total gas cost
    let data_cost = GasConstants.GAS_LOG_DATA * size.value.low;
    let topic_cost = GasConstants.GAS_LOG_TOPIC * NUM_TOPICS;
    let total_cost = Uint(
        GasConstants.GAS_LOG + data_cost + topic_cost + extend_memory.value.cost.value
    );

    let err = charge_gas(total_cost);
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    let memory = evm.value.memory;
    with memory {
        expand_by(extend_memory.value.expand_by);
        let data = memory_read_bytes(memory_start_index, size);
    }

    // Create log entry
    let be_topic1 = U256_to_be_bytes(topic1);
    let be_topic2 = U256_to_be_bytes(topic2);
    let (local _topics: Bytes32*) = alloc();
    assert _topics[0] = be_topic1;
    assert _topics[1] = be_topic2;
    tempvar topics = TupleBytes32(new TupleBytes32Struct(_topics, 2));
    tempvar log_entry = Log(
        new LogStruct(address=evm.value.message.value.current_target, topics=topics, data=data)
    );

    // Check for static context
    if (evm.value.message.value.is_static.value != 0) {
        tempvar err = new ExceptionalHalt(WriteInStaticContext);
        return err;
    }

    // Append log entry
    let logs = evm.value.logs.value;
    assert logs.data[logs.len] = log_entry;
    let len = logs.len + 1;
    EvmImpl.set_logs(TupleLog(new TupleLogStruct(logs.data, len)));

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack_memory(Uint(evm.value.pc.value + 1), stack, memory);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice LOG3 instruction - append log record with three topics
func log3{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    const NUM_TOPICS = 3;

    // STACK
    let stack = evm.value.stack;
    with stack {
        // Pop memory_start_index and size
        let (memory_start_index, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (size, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (topic1, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (topic2, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (topic3, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // GAS
    // Calculate memory expansion cost
    // If the size is greater than 2**128, the memory expansion will trigger an out of gas error.
    if (size.value.high != 0) {
        tempvar err = new ExceptionalHalt(OutOfGasError);
        return err;
    }

    // Calculate memory expansion cost
    tempvar mem_access_tuple = new TupleU256U256(new TupleU256U256Struct(memory_start_index, size));
    tempvar mem_access_list = ListTupleU256U256(new ListTupleU256U256Struct(mem_access_tuple, 1));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, mem_access_list);

    // Calculate total gas cost
    let data_cost = GasConstants.GAS_LOG_DATA * size.value.low;
    let topic_cost = GasConstants.GAS_LOG_TOPIC * NUM_TOPICS;
    let total_cost = Uint(
        GasConstants.GAS_LOG + data_cost + topic_cost + extend_memory.value.cost.value
    );

    let err = charge_gas(total_cost);
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    let memory = evm.value.memory;
    with memory {
        expand_by(extend_memory.value.expand_by);
        let data = memory_read_bytes(memory_start_index, size);
    }

    // Create log entry
    let be_topic1 = U256_to_be_bytes(topic1);
    let be_topic2 = U256_to_be_bytes(topic2);
    let be_topic3 = U256_to_be_bytes(topic3);
    let (local _topics: Bytes32*) = alloc();
    assert _topics[0] = be_topic1;
    assert _topics[1] = be_topic2;
    assert _topics[2] = be_topic3;
    tempvar topics = TupleBytes32(new TupleBytes32Struct(_topics, 3));
    tempvar log_entry = Log(
        new LogStruct(address=evm.value.message.value.current_target, topics=topics, data=data)
    );

    // Check for static context
    if (evm.value.message.value.is_static.value != 0) {
        tempvar err = new ExceptionalHalt(WriteInStaticContext);
        return err;
    }

    // Append log entry
    let logs = evm.value.logs.value;
    assert logs.data[logs.len] = log_entry;
    let len = logs.len + 1;
    EvmImpl.set_logs(TupleLog(new TupleLogStruct(logs.data, len)));

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack_memory(Uint(evm.value.pc.value + 1), stack, memory);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice LOG4 instruction - append log record with four topics
func log4{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    const NUM_TOPICS = 4;

    // STACK
    let stack = evm.value.stack;
    with stack {
        // Pop memory_start_index and size
        let (memory_start_index, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (size, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (topic1, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (topic2, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (topic3, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (topic4, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // GAS
    // Calculate memory expansion cost
    // If the size is greater than 2**128, the memory expansion will trigger an out of gas error.
    if (size.value.high != 0) {
        tempvar err = new ExceptionalHalt(OutOfGasError);
        return err;
    }

    // Calculate memory expansion cost
    tempvar mem_access_tuple = new TupleU256U256(new TupleU256U256Struct(memory_start_index, size));
    tempvar mem_access_list = ListTupleU256U256(new ListTupleU256U256Struct(mem_access_tuple, 1));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, mem_access_list);

    // Calculate total gas cost
    let data_cost = GasConstants.GAS_LOG_DATA * size.value.low;
    let topic_cost = GasConstants.GAS_LOG_TOPIC * NUM_TOPICS;
    let total_cost = Uint(
        GasConstants.GAS_LOG + data_cost + topic_cost + extend_memory.value.cost.value
    );

    let err = charge_gas(total_cost);
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    let memory = evm.value.memory;
    with memory {
        expand_by(extend_memory.value.expand_by);
        let data = memory_read_bytes(memory_start_index, size);
    }

    // Create log entry
    let be_topic1 = U256_to_be_bytes(topic1);
    let be_topic2 = U256_to_be_bytes(topic2);
    let be_topic3 = U256_to_be_bytes(topic3);
    let be_topic4 = U256_to_be_bytes(topic4);
    let (local _topics: Bytes32*) = alloc();
    assert _topics[0] = be_topic1;
    assert _topics[1] = be_topic2;
    assert _topics[2] = be_topic3;
    assert _topics[3] = be_topic4;
    tempvar topics = TupleBytes32(new TupleBytes32Struct(_topics, 4));
    tempvar log_entry = Log(
        new LogStruct(address=evm.value.message.value.current_target, topics=topics, data=data)
    );

    // Check for static context
    if (evm.value.message.value.is_static.value != 0) {
        tempvar err = new ExceptionalHalt(WriteInStaticContext);
        return err;
    }

    // Append log entry
    let logs = evm.value.logs.value;
    assert logs.data[logs.len] = log_entry;
    let len = logs.len + 1;
    EvmImpl.set_logs(TupleLog(new TupleLogStruct(logs.data, len)));

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack_memory(Uint(evm.value.pc.value + 1), stack, memory);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

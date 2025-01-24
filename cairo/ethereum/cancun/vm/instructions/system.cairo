// SPDX-License-Identifier: MIT

from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin, PoseidonBuiltin
from ethereum.cancun.vm.stack import pop
from ethereum.cancun.vm import Evm, EvmImpl
from ethereum.cancun.vm.exceptions import Revert, OutOfGasError
from ethereum.cancun.vm.memory import memory_read_bytes, expand_by
from ethereum.cancun.vm.gas import calculate_gas_extend_memory, charge_gas, GasConstants
from ethereum_types.numeric import U256, Uint, bool
from ethereum.exceptions import EthereumException

from ethereum_types.others import (
    ListTupleU256U256,
    ListTupleU256U256Struct,
    TupleU256U256,
    TupleU256U256Struct,
)
// @notice Revert operation - stop execution and revert state changes, returning data from memory
func revert{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (memory_start_index, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (size, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    // GAS
    // Calculate memory expansion cost
    // If size > 2**128 - 1, OutOfGasError
    if (size.value.high != 0) {
        EvmImpl.set_stack(stack);
        tempvar err = new EthereumException(OutOfGasError);
        return err;
    }
    tempvar extensions_tuple = new TupleU256U256(new TupleU256U256Struct(memory_start_index, size));
    tempvar extensions_list = ListTupleU256U256(new ListTupleU256U256Struct(extensions_tuple, 1));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, extensions_list);

    let err = charge_gas(Uint(extend_memory.value.cost.value));
    if (cast(err, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err;
    }

    // OPERATION
    let memory = evm.value.memory;
    with memory {
        expand_by(extend_memory.value.expand_by);
        let output = memory_read_bytes(memory_start_index, size);
        EvmImpl.set_output(output);
    }

    // Raise revert
    tempvar revert = new EthereumException(Revert);
    EvmImpl.set_stack(stack);
    return revert;
}

// @notice Return operation - stop execution and return data from memory
func return_{range_check_ptr, evm: Evm}() -> EthereumException* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (memory_start_position, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (memory_size, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    // GAS
    // Calculate memory expansion cost
    // If memory_size > 2**128 - 1, OutOfGasError
    if (memory_size.value.high != 0) {
        EvmImpl.set_stack(stack);
        tempvar err = new EthereumException(OutOfGasError);
        return err;
    }

    tempvar extensions_tuple = new TupleU256U256(
        new TupleU256U256Struct(memory_start_position, memory_size)
    );
    tempvar extensions_list = ListTupleU256U256(new ListTupleU256U256Struct(extensions_tuple, 1));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, extensions_list);

    let err = charge_gas(Uint(GasConstants.GAS_ZERO + extend_memory.value.cost.value));
    if (cast(err, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err;
    }

    // OPERATION
    let memory = evm.value.memory;
    with memory {
        expand_by(extend_memory.value.expand_by);
        let output = memory_read_bytes(memory_start_position, memory_size);
        EvmImpl.set_output(output);
    }

    // Stop execution
    EvmImpl.set_running(bool(0));
    EvmImpl.set_memory(memory);
    EvmImpl.set_stack(stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

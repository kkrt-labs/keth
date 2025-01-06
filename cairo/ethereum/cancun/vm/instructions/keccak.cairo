from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.uint256 import uint256_reverse_endian

from ethereum.cancun.vm.stack import pop, push
from ethereum.cancun.vm import Evm, EvmImpl
from ethereum.cancun.vm.exceptions import ExceptionalHalt, OutOfGasError
from ethereum.cancun.vm.memory import memory_read_bytes, expand_by
from ethereum.cancun.vm.gas import calculate_gas_extend_memory, charge_gas, GasConstants
from ethereum_types.numeric import U256, U256Struct, Uint
from ethereum.crypto.hash import keccak256
from ethereum.utils.numeric import ceil32, divmod, U256_from_be_bytes
from ethereum_types.others import (
    ListTupleU256U256,
    ListTupleU256U256Struct,
    TupleU256U256,
    TupleU256U256Struct,
)

// @notice Computes Keccak-256 hash of a region of memory
func keccak{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*, evm: Evm}(
    ) -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
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
    // If the size is greater than 2**128, the memory expansion will trigger an out of gas error.
    if (size.value.high != 0) {
        tempvar err = new ExceptionalHalt(OutOfGasError);
        return err;
    }
    let ceil32_size = ceil32(Uint(size.value.low));
    let (words, _) = divmod(ceil32_size.value, 32);
    let word_gas_cost = GasConstants.GAS_KECCAK256_WORD * words;

    tempvar mem_access_tuple = new TupleU256U256(new TupleU256U256Struct(memory_start_index, size));
    tempvar mem_access_list = ListTupleU256U256(new ListTupleU256U256Struct(mem_access_tuple, 1));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, mem_access_list);

    // Calculate memory expansion cost
    let total_gas = Uint(
        GasConstants.GAS_KECCAK256 + word_gas_cost + extend_memory.value.cost.value
    );

    let err = charge_gas(total_gas);
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    let memory = evm.value.memory;
    with memory {
        expand_by(extend_memory.value.expand_by);
        let data = memory_read_bytes(memory_start_index, size);
    }

    let hash = keccak256(data);

    // Push result to stack
    with stack {
        let value = U256_from_be_bytes(hash);
        let err = push(value);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack_memory(Uint(evm.value.pc.value + 1), stack, memory);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

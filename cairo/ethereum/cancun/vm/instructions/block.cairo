from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.math_cmp import is_nn, is_in_range

from ethereum_types.numeric import U256, U256Struct, Uint
from ethereum.cancun.vm import Evm, EvmImpl
from ethereum.cancun.vm.exceptions import ExceptionalHalt
from ethereum.cancun.vm.gas import charge_gas, GasConstants
from ethereum.cancun.vm.stack import Stack, pop, push
from ethereum.utils.numeric import U256_from_be_bytes
from src.utils.bytes import felt_to_bytes20_little
from src.utils.utils import Helpers

// @notice Get the hash of one of the 256 most recent complete blocks
func block_hash{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (block_number, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // GAS
    let err = charge_gas(Uint(GasConstants.GAS_BLOCK_HASH));
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    with stack {
        let err = Internals.blockhash(evm, block_number);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Get the current block's beneficiary address
func coinbase{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;

    // GAS
    let err = charge_gas(Uint(GasConstants.GAS_BASE));
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    let coinbase = evm.value.env.value.coinbase;
    let (coinbase_bytes: felt*) = alloc();
    felt_to_bytes20_little(coinbase_bytes, coinbase.value);
    let coinbase_uint256 = Helpers.bytes_to_uint256(20, coinbase_bytes);

    with stack {
        let err = push(U256(new U256Struct(coinbase_uint256.low, coinbase_uint256.high)));
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Get the current block's timestamp
func timestamp{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;

    // GAS
    let err = charge_gas(Uint(GasConstants.GAS_BASE));
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    with stack {
        let err = push(evm.value.env.value.time);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Get the current block's number
func number{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;

    // GAS
    let err = charge_gas(Uint(GasConstants.GAS_BASE));
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    with stack {
        let err = push(U256(new U256Struct(evm.value.env.value.number.value, 0)));
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Get the current block's prev_randao value
func prev_randao{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;

    // GAS
    let err = charge_gas(Uint(GasConstants.GAS_BASE));
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    let prev_randao_uint256 = U256_from_be_bytes(evm.value.env.value.prev_randao);
    with stack {
        let err = push(prev_randao_uint256);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Get the current block's gas limit
func gas_limit{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;

    // GAS
    let err = charge_gas(Uint(GasConstants.GAS_BASE));
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    with stack {
        let err = push(U256(new U256Struct(evm.value.env.value.gas_limit.value, 0)));
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Get the chain ID
func chain_id{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;

    // GAS
    let err = charge_gas(Uint(GasConstants.GAS_BASE));
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    with stack {
        let err = push(U256(new U256Struct(evm.value.env.value.chain_id.value, 0)));
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

namespace Internals {
    func blockhash{range_check_ptr, stack: Stack}(
        evm: Evm, block_number: U256
    ) -> ExceptionalHalt* {
        alloc_locals;
        if (block_number.value.high != 0) {
            with stack {
                let err = push(U256(new U256Struct(0, 0)));
                if (cast(err, felt) != 0) {
                    return err;
                }
            }
            let ok = cast(0, ExceptionalHalt*);
            return ok;
        }

        let lower_bound_unsafe = evm.value.env.value.number.value - 256;
        tempvar lower_bound = is_nn(lower_bound_unsafe) * lower_bound_unsafe;
        let in_range = is_in_range(
            block_number.value.low, lower_bound, evm.value.env.value.number.value
        );

        if (in_range == FALSE) {
            with stack {
                let err = push(U256(new U256Struct(0, 0)));
                if (cast(err, felt) != 0) {
                    return err;
                }
            }
            let ok = cast(0, ExceptionalHalt*);
            return ok;
        }

        let index_from_end = evm.value.env.value.block_hashes.value.len -
            evm.value.env.value.number.value + block_number.value.low;
        let block_hashes = evm.value.env.value.block_hashes.value.data[index_from_end];
        with stack {
            let err = push(U256(new U256Struct(block_hashes.value.low, block_hashes.value.high)));
            if (cast(err, felt) != 0) {
                return err;
            }
        }
        let ok = cast(0, ExceptionalHalt*);
        return ok;
    }
}

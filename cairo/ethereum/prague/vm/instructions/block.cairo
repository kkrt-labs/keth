from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, PoseidonBuiltin, ModBuiltin
from starkware.cairo.common.math_cmp import is_nn, is_in_range

from ethereum_types.numeric import U256, U256Struct, Uint
from ethereum.prague.vm.evm_impl import Evm, EvmImpl
from ethereum.prague.blocks import TupleLog, TupleLogStruct
from ethereum.exceptions import EthereumException
from ethereum.prague.vm.gas import charge_gas, GasConstants
from ethereum.prague.vm.stack import Stack, pop, push
from ethereum.prague.vm.env_impl import BlockEnvironment
from ethereum.utils.numeric import U256_from_be_bytes32
from legacy.utils.bytes import felt_to_bytes20_little
from legacy.utils.utils import Helpers
from starkware.cairo.common.memcpy import memcpy

// @notice Get the hash of one of the 256 most recent complete blocks
func block_hash{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (block_number, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    // GAS
    let err = charge_gas(Uint(GasConstants.GAS_BLOCK_HASH));
    if (cast(err, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err;
    }

    // OPERATION
    with stack {
        // Pass evm.message.block_env to Internals.blockhash if it needs env fields
        let err = Internals.blockhash(evm.value.message.value.block_env, block_number);
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Get the current block's beneficiary address
func coinbase{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;

    // GAS
    let err = charge_gas(Uint(GasConstants.GAS_BASE));
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    let coinbase_addr = evm.value.message.value.block_env.value.coinbase;
    let (coinbase_bytes: felt*) = alloc();
    felt_to_bytes20_little(coinbase_bytes, coinbase_addr.value);
    let coinbase_uint256 = Helpers.bytes_to_uint256(20, coinbase_bytes);

    with stack {
        let err = push(U256(new U256Struct(coinbase_uint256.low, coinbase_uint256.high)));
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Get the current block's timestamp
func timestamp{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
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
        let err = push(evm.value.message.value.block_env.value.time);
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Get the current block's number
func number{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
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
        let err = push(U256(new U256Struct(evm.value.message.value.block_env.value.number.value, 0)));
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Get the current block's prev_randao value
func prev_randao{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;

    // GAS
    let err = charge_gas(Uint(GasConstants.GAS_BASE));
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    let prev_randao_uint256 = U256_from_be_bytes32(evm.value.message.value.block_env.value.prev_randao);
    with stack {
        let err = push(prev_randao_uint256);
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Get the current block's gas limit
func gas_limit{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
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
        let err = push(U256(new U256Struct(evm.value.message.value.block_env.value.block_gas_limit.value, 0)));
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Get the chain ID
func chain_id{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
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
        let err = push(U256(new U256Struct(evm.value.message.value.block_env.value.chain_id.value, 0)));
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

namespace Internals {
    func blockhash{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, stack: Stack}(
        block_env: BlockEnvironment, block_number: U256
    ) -> EthereumException* {
        alloc_locals;
        if (block_number.value.high != 0) {
            with stack {
                let err = push(U256(new U256Struct(0, 0)));
                if (cast(err, felt) != 0) {
                    return err;
                }
            }
            let ok = cast(0, EthereumException*);
            return ok;
        }

        let lower_bound_unsafe = block_env.value.number.value - 256;

        tempvar lower_bound = is_nn(lower_bound_unsafe) * lower_bound_unsafe;
        let in_range = is_in_range(
            block_number.value.low, lower_bound, block_env.value.number.value
        );

        if (in_range == FALSE) {
            with stack {
                let err = push(U256(new U256Struct(0, 0)));
                if (cast(err, felt) != 0) {
                    return err;
                }
            }
            let ok = cast(0, EthereumException*);
            return ok;
        }

        let index_from_start = block_env.value.block_hashes.value.len - (block_env.value.number.value - block_number.value.low);


        let block_hash_at_index = block_env.value.block_hashes.value.data[index_from_start];
        with stack {
            let hash_u256 = U256_from_be_bytes32(block_hash_at_index);
            let err = push(hash_u256);
            if (cast(err, felt) != 0) {
                return err;
            }
        }
        let ok = cast(0, EthereumException*);
        return ok;
    }
}

func _append_logs{logs: TupleLog}(new_logs: TupleLog) {
    let src_len = new_logs.value.len;
    if (src_len == 0) {
        return ();
    }
    let len = logs.value.len;
    let dst = logs.value.data + len;
    let src = new_logs.value.data;
    memcpy(dst, src, src_len);
    tempvar logs = TupleLog(new TupleLogStruct(data=logs.value.data, len=len + src_len));
    return ();
}

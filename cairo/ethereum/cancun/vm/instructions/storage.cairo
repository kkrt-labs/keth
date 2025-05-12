from ethereum.cancun.vm.stack import pop, push
from ethereum.cancun.vm.evm_impl import Evm, EvmImpl
from ethereum.cancun.vm.env_impl import BlockEnvImpl, TransactionEnvImpl
from ethereum.exceptions import EthereumException
from ethereum.cancun.vm.exceptions import WriteInStaticContext, OutOfGasError
from ethereum.cancun.vm.gas import charge_gas, GasConstants
from ethereum.utils.numeric import U256__eq__
from ethereum.cancun.state import (
    get_storage,
    get_storage_original,
    set_storage,
    get_transient_storage,
    set_transient_storage,
)
from ethereum.cancun.fork_types import (
    SetTupleAddressBytes32,
    SetTupleAddressBytes32DictAccess,
    SetTupleAddressBytes32Struct,
    TupleAddressBytes32,
    TupleAddressBytes32Struct,
)
from ethereum_types.numeric import U256, U256Struct, Uint
from ethereum.utils.numeric import U256_to_be_bytes
from legacy.utils.dict import hashdict_read, hashdict_write

from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, PoseidonBuiltin, ModBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.math_cmp import is_le

// @notice Loads to the stack the value corresponding to a certain key from the
// storage of the current account.
func sload{
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
        let (key, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }
    // Gas
    // Get the entry from the accessed storage keys
    let key_bytes32 = U256_to_be_bytes(key);
    tempvar accessed_tuple = TupleAddressBytes32(
        new TupleAddressBytes32Struct(evm.value.message.value.current_target, key_bytes32)
    );
    let (serialized_keys: felt*) = alloc();
    assert serialized_keys[0] = accessed_tuple.value.address.value;
    assert serialized_keys[1] = accessed_tuple.value.bytes32.value.low;
    assert serialized_keys[2] = accessed_tuple.value.bytes32.value.high;
    let dict_ptr = cast(evm.value.accessed_storage_keys.value.dict_ptr, DictAccess*);
    with dict_ptr {
        let (is_present) = hashdict_read(3, serialized_keys);
        if (is_present == 0) {
            // If the entry is not in the accessed storage keys, add it
            hashdict_write(3, serialized_keys, 1);
            tempvar range_check_ptr = range_check_ptr;
            tempvar dict_ptr = dict_ptr;
        } else {
            tempvar range_check_ptr = range_check_ptr;
            tempvar dict_ptr = dict_ptr;
        }
    }

    let range_check_ptr = [ap - 2];
    let dict_ptr = cast([ap - 1], DictAccess*);

    let new_dict_ptr = cast(dict_ptr, SetTupleAddressBytes32DictAccess*);
    tempvar new_accessed_storage_keys = SetTupleAddressBytes32(
        new SetTupleAddressBytes32Struct(
            evm.value.accessed_storage_keys.value.dict_ptr_start, new_dict_ptr
        ),
    );
    EvmImpl.set_accessed_storage_keys(new_accessed_storage_keys);

    let access_gas_cost = (is_present * GasConstants.GAS_WARM_ACCESS) + (1 - is_present) *
        GasConstants.GAS_COLD_SLOAD;
    let err = charge_gas(Uint(access_gas_cost));
    if (cast(err, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err;
    }

    // OPERATION
    let block_env = evm.value.message.value.block_env;
    let state = block_env.value.state;
    with state, stack {
        let value = get_storage(evm.value.message.value.current_target, key_bytes32);

        // Rebind state, env, stack, and accessed_storage_keys since it's the last time they are used
        let block_env = evm.value.message.value.block_env;
        BlockEnvImpl.set_state{block_env=block_env}(state);
        EvmImpl.set_block_env(block_env);

        // Push cannot fail with StackOverflowError, 1 element was popped
        push(value);
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Stores a value at a certain key in the current context's storage.
func sstore{
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
        let (key, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (new_value, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    let is_gas_left_not_enough = is_le(evm.value.gas_left.value, GasConstants.GAS_CALL_STIPEND);
    if (is_gas_left_not_enough != 0) {
        EvmImpl.set_stack(stack);
        tempvar err = new EthereumException(OutOfGasError);
        return err;
    }

    // Get storage values
    let key_bytes32 = U256_to_be_bytes(key);
    let state = evm.value.message.value.block_env.value.state;
    let current_target = evm.value.message.value.current_target;
    with state {
        let original_value = get_storage_original(current_target, key_bytes32);
        let current_value = get_storage(current_target, key_bytes32);
    }

    // Gas calculation
    // Check accessed storage keys
    tempvar accessed_tuple = TupleAddressBytes32(
        new TupleAddressBytes32Struct(current_target, key_bytes32)
    );
    let (serialized_keys: felt*) = alloc();
    assert serialized_keys[0] = accessed_tuple.value.address.value;
    assert serialized_keys[1] = accessed_tuple.value.bytes32.value.low;
    assert serialized_keys[2] = accessed_tuple.value.bytes32.value.high;
    let dict_ptr = cast(evm.value.accessed_storage_keys.value.dict_ptr, DictAccess*);
    with dict_ptr {
        let (is_present) = hashdict_read(3, serialized_keys);
        if (is_present == 0) {
            hashdict_write(3, serialized_keys, 1);
            tempvar gas_cost = GasConstants.GAS_COLD_SLOAD;
            tempvar range_check_ptr = range_check_ptr;
            tempvar dict_ptr = dict_ptr;
        } else {
            tempvar gas_cost = 0;
            tempvar range_check_ptr = range_check_ptr;
            tempvar dict_ptr = dict_ptr;
        }
    }
    let gas_cost = [ap - 3];
    let range_check_ptr = [ap - 2];
    let dict_ptr = cast([ap - 1], DictAccess*);

    let new_dict_ptr = cast(dict_ptr, SetTupleAddressBytes32DictAccess*);
    tempvar new_accessed_storage_keys = SetTupleAddressBytes32(
        new SetTupleAddressBytes32Struct(
            evm.value.accessed_storage_keys.value.dict_ptr_start, new_dict_ptr
        ),
    );

    // Calculate storage gas cost
    tempvar zero_u256 = U256(new U256Struct(0, 0));
    let is_original_eq_current = U256__eq__(original_value, current_value);
    let is_current_eq_new = U256__eq__(current_value, new_value);
    let is_original_zero = U256__eq__(original_value, zero_u256);
    let is_original_eq_current_and_current_diff_new = is_original_eq_current.value * (
        1 - is_current_eq_new.value
    );
    if (is_original_eq_current_and_current_diff_new != 0) {
        if (is_original_zero.value != 0) {
            tempvar gas_cost = gas_cost + GasConstants.GAS_STORAGE_SET;
        } else {
            tempvar gas_cost = gas_cost + (
                GasConstants.GAS_STORAGE_UPDATE - GasConstants.GAS_COLD_SLOAD
            );
        }
    } else {
        tempvar gas_cost = gas_cost + GasConstants.GAS_WARM_ACCESS;
    }
    let gas_cost = [ap - 1];

    local current_refund_counter = evm.value.refund_counter;
    local refund_counter;
    // Refund calculation
    if (is_current_eq_new.value == 0) {
        let refund_counter_res = _calculate_refund_counter_current_eq_new(
            current_refund_counter, original_value, current_value, new_value, zero_u256
        );
        assert refund_counter = refund_counter_res;
    } else {
        assert refund_counter = current_refund_counter;
    }

    // Charge gas
    let err = charge_gas(Uint(gas_cost));
    if (cast(err, felt) != 0) {
        // Update EVM state
        let block_env = evm.value.message.value.block_env;
        BlockEnvImpl.set_state{block_env=block_env}(state);
        EvmImpl.set_block_env(block_env);
        EvmImpl.set_accessed_storage_keys(new_accessed_storage_keys);
        EvmImpl.set_refund_counter(refund_counter);
        EvmImpl.set_stack(stack);
        return err;
    }
    // Check static call
    if (evm.value.message.value.is_static.value != 0) {
        // Update EVM state
        let block_env = evm.value.message.value.block_env;
        BlockEnvImpl.set_state{block_env=block_env}(state);
        EvmImpl.set_block_env(block_env);
        EvmImpl.set_accessed_storage_keys(new_accessed_storage_keys);
        EvmImpl.set_refund_counter(refund_counter);
        EvmImpl.set_stack(stack);
        tempvar err = new EthereumException(WriteInStaticContext);
        return err;
    }

    // Set storage
    with state {
        set_storage(current_target, key_bytes32, new_value);
    }

    // Update EVM state
    let block_env = evm.value.message.value.block_env;
    BlockEnvImpl.set_state{block_env=block_env}(state);
    EvmImpl.set_block_env(block_env);
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    EvmImpl.set_refund_counter(refund_counter);
    EvmImpl.set_accessed_storage_keys(new_accessed_storage_keys);
    let ok = cast(0, EthereumException*);
    return ok;
}

// # see https://github.com/ethereum/execution-specs/blob/6e652281164025f1f4227f6e5b0036c1bbd27347/src/ethereum/cancun/vm/instructions/storage.py#L104
func _calculate_refund_counter_current_eq_new(
    current_refund_counter: felt,
    original_value: U256,
    current_value: U256,
    new_value: U256,
    zero_u256: U256,
) -> felt {
    alloc_locals;

    local refund_counter;
    let is_original_zero = U256__eq__(original_value, zero_u256);
    let is_original_eq_new = U256__eq__(original_value, new_value);
    let is_current_zero = U256__eq__(current_value, zero_u256);
    let is_new_zero = U256__eq__(new_value, zero_u256);

    if (is_original_zero.value == 0 and is_current_zero.value == 0 and is_new_zero.value != 0) {
        assert refund_counter = current_refund_counter + GasConstants.GAS_STORAGE_CLEAR_REFUND;
        return refund_counter;
    }

    local temp_refund_counter;
    if (is_original_zero.value == 0) {
        if (is_current_zero.value != 0) {
            assert temp_refund_counter = current_refund_counter -
                GasConstants.GAS_STORAGE_CLEAR_REFUND;
        } else {
            assert temp_refund_counter = current_refund_counter;
        }
    } else {
        assert temp_refund_counter = current_refund_counter;
    }
    if (is_original_eq_new.value != 0) {
        if (is_original_zero.value != 0) {
            assert refund_counter = temp_refund_counter + (
                GasConstants.GAS_STORAGE_SET - GasConstants.GAS_WARM_ACCESS
            );
        } else {
            assert refund_counter = temp_refund_counter + (
                GasConstants.GAS_STORAGE_UPDATE -
                GasConstants.GAS_COLD_SLOAD -
                GasConstants.GAS_WARM_ACCESS
            );
        }
    } else {
        assert refund_counter = temp_refund_counter;
    }
    return refund_counter;
}

// @notice Loads to the stack the value corresponding to a certain key from the
// transient storage of the current account.
func tload{
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
        let (key, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    // GAS
    let err = charge_gas(Uint(GasConstants.GAS_WARM_ACCESS));
    if (cast(err, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err;
    }

    // OPERATION
    let tx_env = evm.value.message.value.tx_env;
    let transient_storage = tx_env.value.transient_storage;
    let key_bytes32 = U256_to_be_bytes(key);
    let value = get_transient_storage{transient_storage=transient_storage}(
        evm.value.message.value.current_target, key_bytes32
    );
    // Push cannot fail with StackOverflowError, 1 element was popped
    push{stack=stack}(value);

    // PROGRAM COUNTER
    // Transient storage is part of tx_env, which is part of message
    let tx_env = evm.value.message.value.tx_env;
    TransactionEnvImpl.set_transient_storage{tx_env=tx_env}(transient_storage);
    EvmImpl.set_tx_env(tx_env);
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Stores a value at a certain key in the current context's transient storage.
func tstore{
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
        let (key, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (new_value, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    // GAS
    let err = charge_gas(Uint(GasConstants.GAS_WARM_ACCESS));
    if (cast(err, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err;
    }

    // Check for static call
    if (evm.value.message.value.is_static.value != 0) {
        EvmImpl.set_stack(stack);
        tempvar err = new EthereumException(WriteInStaticContext);
        return cast(err, EthereumException*);
    }

    // OPERATION
    let tx_env = evm.value.message.value.tx_env;
    let transient_storage = tx_env.value.transient_storage;
    let key_bytes32 = U256_to_be_bytes(key);
    set_transient_storage{transient_storage=transient_storage}(
        evm.value.message.value.current_target, key_bytes32, new_value
    );

    // PROGRAM COUNTER
    let tx_env = evm.value.message.value.tx_env;
    TransactionEnvImpl.set_transient_storage{tx_env=tx_env}(transient_storage);
    EvmImpl.set_tx_env(tx_env);
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

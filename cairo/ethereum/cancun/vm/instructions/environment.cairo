from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, PoseidonBuiltin
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.math import split_felt

from ethereum_types.bytes import Bytes32, Bytes32Struct
from ethereum_types.numeric import U256, U256Struct, Uint, UnionUintU256, UnionUintU256Enum
from ethereum.cancun.fork_types import Address, SetAddress, SetAddressStruct, SetAddressDictAccess
from ethereum.cancun.vm import Evm, EvmImpl, EnvImpl
from ethereum.cancun.vm.exceptions import ExceptionalHalt
from ethereum.cancun.vm.gas import charge_gas, GasConstants
from ethereum.cancun.vm.stack import Stack, push, pop
from ethereum.cancun.state import get_account
from ethereum.cancun.utils.address import to_address

from ethereum.utils.numeric import U256_lt, U256_from_be_bytes, U256_from_be_bytes20

from src.utils.bytes import felt_to_bytes20_little
from src.utils.dict import hashdict_read, hashdict_write

// @notice Pushes the address of the current executing account to the stack.
func address{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, evm: Evm}() -> ExceptionalHalt* {
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
        let address_u256 = U256_from_be_bytes20(evm.value.message.value.current_target);
        let err = push(address_u256);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

func balance{range_check_ptr, poseidon_ptr: PoseidonBuiltin*, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (address_u256, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    // GAS
    let accessed_addresses = evm.value.accessed_addresses;
    let accessed_addresses_ptr = cast(accessed_addresses.value.dict_ptr, DictAccess*);
    tempvar address_u256_ = UnionUintU256(new UnionUintU256Enum(cast(0, Uint*), address_u256));
    let address_ = to_address(address_u256_);
    tempvar address = new Address(address_.value);
    let (is_present) = hashdict_read{dict_ptr=accessed_addresses_ptr}(1, &address.value);
    if (is_present == 0) {
        // If the entry is not in the accessed storage keys, add it
        hashdict_write{dict_ptr=accessed_addresses_ptr}(1, &address.value, 1);
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar accessed_addresses_ptr = accessed_addresses_ptr;
    } else {
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar accessed_addresses_ptr = accessed_addresses_ptr;
    }
    let poseidon_ptr = cast([ap - 2], PoseidonBuiltin*);
    let new_accessed_addresses_ptr = cast([ap - 1], SetAddressDictAccess*);
    tempvar new_accessed_addresses = SetAddress(
        new SetAddressStruct(
            evm.value.accessed_addresses.value.dict_ptr_start, new_accessed_addresses_ptr
        ),
    );
    EvmImpl.set_accessed_addresses(new_accessed_addresses);

    let access_gas_cost = (is_present * GasConstants.GAS_WARM_ACCESS) + (1 - is_present) *
        GasConstants.GAS_COLD_ACCOUNT_ACCESS;
    let err = charge_gas(Uint(access_gas_cost));
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    with stack {
        let err = push(evm.value.message.value.value);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

func origin{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, evm: Evm}() -> ExceptionalHalt* {
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
        let origin_u256 = U256_from_be_bytes20(evm.value.env.value.origin);

        let err = push(origin_u256);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Push the address of the caller onto the stack
func caller{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, evm: Evm}() -> ExceptionalHalt* {
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
        let caller_u256 = U256_from_be_bytes20(evm.value.message.value.caller);
        let err = push(caller_u256);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Push the value (in wei) sent with the call onto the stack
func callvalue{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
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
        let err = push(evm.value.message.value.value);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Push the size of code running in current environment onto the stack
func codesize{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
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
        // max codesize is 24kb
        tempvar code_len = U256(new U256Struct(evm.value.code.value.len, 0));
        let err = push(code_len);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Push the gas price used in current environment onto the stack
func gasprice{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
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
        // gas price is a u64
        tempvar gas_price = U256(new U256Struct(evm.value.env.value.gas_price.value, 0));
        let err = push(gas_price);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Push the size of the return data buffer onto the stack
func returndatasize{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
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
        // any returndata bigger would produce an OOG upstream.
        let err = push(U256(new U256Struct(evm.value.return_data.value.len, 0)));
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Push the balance of the current address to the stack
func self_balance{range_check_ptr, poseidon_ptr: PoseidonBuiltin*, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;

    // GAS
    let err = charge_gas(Uint(GasConstants.GAS_FAST_STEP));
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    let state = evm.value.env.value.state;
    let account = get_account{state=state}(evm.value.message.value.current_target);
    let env = evm.value.env;
    EnvImpl.set_state{env=env}(state);
    EvmImpl.set_env(env);

    with stack {
        let err = push(account.value.balance);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Push the base fee of the current block onto the stack
func base_fee{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
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
        // base fee is a u64
        tempvar base_fee = U256(new U256Struct(evm.value.env.value.base_fee_per_gas.value, 0));
        let err = push(base_fee);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Gets the versioned hash at a particular index
func blob_hash{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;

    // STACK
    let stack = evm.value.stack;
    with stack {
        let (index, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // GAS
    let err = charge_gas(Uint(GasConstants.GAS_BLOBHASH_OPCODE));
    if (cast(err, felt) != 0) {
        return err;
    }

    let blob_hashes = evm.value.env.value.blob_versioned_hashes;

    // If index is within bounds, get the hash at that index
    // Otherwise return zero bytes
    let (high, low) = split_felt(blob_hashes.value.len);
    let in_bounds = U256_lt(index, U256(new U256Struct(low, high)));
    if (in_bounds.value == 0) {
        tempvar blob_hash = Bytes32(new Bytes32Struct(0, 0));
    } else {
        tempvar blob_hash = blob_hashes.value.data[index.value.low];
    }

    // Push result to stack
    let res = U256_from_be_bytes(blob_hash);
    with stack {
        let err = push(res);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, PoseidonBuiltin, KeccakBuiltin
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.math import split_felt
from starkware.cairo.common.uint256 import uint256_lt
from starkware.cairo.common.math_cmp import is_le

from ethereum_types.bytes import Bytes32, Bytes32Struct, Bytes20
from ethereum_types.others import (
    ListTupleU256U256,
    ListTupleU256U256Struct,
    TupleU256U256,
    TupleU256U256Struct,
)
from ethereum_types.numeric import U256, U256Struct, Uint, UnionUintU256, UnionUintU256Enum
from ethereum.cancun.fork_types import (
    Address,
    Account__eq__,
    EMPTY_ACCOUNT,
    OptionalAccount,
    SetAddress,
    SetAddressStruct,
    SetAddressDictAccess,
)
from ethereum.cancun.vm import Evm, EvmImpl, EnvImpl
from ethereum.cancun.vm.exceptions import ExceptionalHalt, OutOfGasError, OutOfBoundsRead
from ethereum.cancun.vm.gas import (
    charge_gas,
    GasConstants,
    calculate_gas_extend_memory,
    calculate_blob_gas_price,
)
from ethereum.cancun.vm.memory import buffer_read, memory_write, expand_by
from ethereum.cancun.vm.stack import Stack, push, pop
from ethereum.cancun.state import get_account
from ethereum.cancun.utils.address import to_address

from ethereum.crypto.hash import keccak256

from ethereum.utils.numeric import (
    U256_from_be_bytes,
    U256_from_be_bytes20,
    ceil32,
    divmod,
    U256_to_be_bytes,
)

from src.utils.bytes import felt_to_bytes20_little
from src.utils.dict import hashdict_read, hashdict_write
from src.utils.utils import Helpers

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
    // Get the account from state
    let state = evm.value.env.value.state;
    let account = get_account{state=state}([address]);
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

func returndatacopy{range_check_ptr: felt, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (memory_start_index, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (returndata_start_position, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (size, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
    }
    if (size.value.high != 0) {
        tempvar err = new ExceptionalHalt(OutOfGasError);
        return err;
    }

    let ceil32_size = ceil32(Uint(size.value.low));
    let (words, _) = divmod(ceil32_size.value, 32);
    let return_data_copy_gas_cost = GasConstants.GAS_RETURN_DATA_COPY * words;
    // Calculate memory expansion cost
    tempvar extensions_tuple = new TupleU256U256(new TupleU256U256Struct(memory_start_index, size));
    tempvar extensions_list = ListTupleU256U256(new ListTupleU256U256Struct(extensions_tuple, 1));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, extensions_list);
    let err = charge_gas(
        Uint(GasConstants.GAS_VERY_LOW + return_data_copy_gas_cost + extend_memory.value.cost.value)
    );
    if (cast(err, felt) != 0) {
        return err;
    }

    let memory = evm.value.memory;
    // Check if the read on return_data is in bounds
    // If the start position is greater than 2 ** 128, then it is almost surely out of bounds
    if (returndata_start_position.value.high != 0) {
        tempvar err = new ExceptionalHalt(OutOfBoundsRead);
        return err;
    }
    // Check if returndata_start_position and size are each less than 2**128, so that their
    // sum is less than 2**129, which fits into a felt. We can then be sure that
    // size.value.low + returndata_start_position.value.low won't wrap around the PRIME.
    assert [range_check_ptr] = returndata_start_position.value.low;
    let range_check_ptr = range_check_ptr + 1;
    assert [range_check_ptr] = size.value.low;
    let range_check_ptr = range_check_ptr + 1;
    let is_in_bounds = is_le(
        size.value.low + returndata_start_position.value.low, evm.value.return_data.value.len
    );
    if (is_in_bounds == 0) {
        tempvar err = new ExceptionalHalt(OutOfBoundsRead);
        return err;
    }

    with memory {
        expand_by(extend_memory.value.expand_by);
        let value = buffer_read(evm.value.return_data, returndata_start_position, size);
        memory_write(memory_start_index, value);
    }
    EvmImpl.set_pc_stack_memory(Uint(evm.value.pc.value + 1), stack, memory);
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
    let (in_bounds) = uint256_lt([index.value], U256Struct(low, high));
    if (in_bounds == 0) {
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

func codecopy{range_check_ptr: felt, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;

    // STACK
    let stack = evm.value.stack;
    with stack {
        let (memory_start_index, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (code_start_index, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (size, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // Gas
    // OutOfGasError if size > 2**128
    if (size.value.high != 0) {
        tempvar err = new ExceptionalHalt(OutOfGasError);
        return err;
    }
    let ceil32_size = ceil32(Uint(size.value.low));
    let (words, _) = divmod(ceil32_size.value, 32);
    let copy_gas_cost = GasConstants.GAS_COPY * words;
    // Calculate memory expansion cost
    tempvar extensions_tuple = new TupleU256U256(new TupleU256U256Struct(memory_start_index, size));
    tempvar extensions_list = ListTupleU256U256(new ListTupleU256U256Struct(extensions_tuple, 1));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, extensions_list);

    // copy_gas_cost in [0, 3 * 2**123)
    // extend_memory.value.cost.value is < 2**110 (see calculate_gas_extend_memory)
    // Hence sum cannot overflow
    let err = charge_gas(
        Uint(GasConstants.GAS_VERY_LOW + copy_gas_cost + extend_memory.value.cost.value)
    );
    if (cast(err, felt) != 0) {
        return err;
    }
    let memory = evm.value.memory;
    with memory {
        expand_by(extend_memory.value.expand_by);
        let value = buffer_read(evm.value.code, code_start_index, size);
        memory_write(memory_start_index, value);
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack_memory(Uint(evm.value.pc.value + 1), stack, memory);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Get the code size of an external contract
func extcodesize{
    range_check_ptr, poseidon_ptr: PoseidonBuiltin*, bitwise_ptr: BitwiseBuiltin*, evm: Evm
}() -> ExceptionalHalt* {
    alloc_locals;

    // STACK
    let stack = evm.value.stack;
    with stack {
        let (address_u256, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
    }

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
    // Get the account from state
    let state = evm.value.env.value.state;
    let account = get_account{state=state}([address]);
    let env = evm.value.env;
    EnvImpl.set_state{env=env}(state);
    EvmImpl.set_env(env);

    // Get code size and push to stack
    tempvar code_size_u256 = U256(new U256Struct(account.value.code.value.len, 0));
    with stack {
        let err = push(code_size_u256);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Copy a portion of an account's code to memory
func extcodecopy{
    range_check_ptr, poseidon_ptr: PoseidonBuiltin*, bitwise_ptr: BitwiseBuiltin*, evm: Evm
}() -> ExceptionalHalt* {
    alloc_locals;

    // STACK
    let stack = evm.value.stack;
    with stack {
        let (address_u256, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (memory_start_index, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (code_start_index, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (size, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // Gas
    // OutOfGasError if size > 2**128
    if (size.value.high != 0) {
        tempvar err = new ExceptionalHalt(OutOfGasError);
        return err;
    }
    let ceil32_size = ceil32(Uint(size.value.low));
    let (words, _) = divmod(ceil32_size.value, 32);
    let copy_gas_cost = GasConstants.GAS_COPY * words;

    // Calculate memory expansion cost
    tempvar extensions_tuple = new TupleU256U256(new TupleU256U256Struct(memory_start_index, size));
    tempvar extensions_list = ListTupleU256U256(new ListTupleU256U256Struct(extensions_tuple, 1));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, extensions_list);

    // Check if address is in accessed_addresses
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
    let total_gas = Uint(access_gas_cost + copy_gas_cost + extend_memory.value.cost.value);
    let err = charge_gas(total_gas);
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    // Get the account code from state
    let state = evm.value.env.value.state;
    let account = get_account{state=state}([address]);
    let env = evm.value.env;
    EnvImpl.set_state{env=env}(state);
    EvmImpl.set_env(env);

    let memory = evm.value.memory;
    with memory {
        expand_by(extend_memory.value.expand_by);
        let value = buffer_read(account.value.code, code_start_index, size);
        memory_write(memory_start_index, value);
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack_memory(Uint(evm.value.pc.value + 1), stack, memory);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Returns the keccak256 hash of a contract's bytecode
func extcodehash{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> ExceptionalHalt* {
    alloc_locals;

    // STACK
    let stack = evm.value.stack;
    with stack {
        let (address_u256, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
    }

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
    // Get the account from state
    let state = evm.value.env.value.state;
    let account = get_account{state=state}([address]);
    let env = evm.value.env;
    EnvImpl.set_state{env=env}(state);
    EvmImpl.set_env(env);

    let _empty_account = EMPTY_ACCOUNT();
    let empty_account = OptionalAccount(_empty_account.value);
    let is_empty_account = Account__eq__(OptionalAccount(account.value), empty_account);

    // If account is empty, push 0
    if (is_empty_account.value != 0) {
        tempvar code_hash_u256 = U256(new U256Struct(0, 0));

        tempvar keccak_ptr = keccak_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
    } else {
        // Calculate keccak256 hash of code and push to stack
        let code_hash = keccak256(account.value.code);
        tempvar code_hash_u256 = U256(new U256Struct(code_hash.value.low, code_hash.value.high));
        let code_hash_bytes32 = U256_to_be_bytes(code_hash_u256);
        tempvar code_hash_u256 = U256(code_hash_bytes32.value);

        tempvar keccak_ptr = keccak_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
    }

    let keccak_ptr = cast([ap - 4], KeccakBuiltin*);
    let poseidon_ptr = cast([ap - 3], PoseidonBuiltin*);
    let range_check_ptr = [ap - 2];
    let bitwise_ptr = cast([ap - 1], BitwiseBuiltin*);

    with stack {
        let err = push(code_hash_u256);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

func blob_base_fee{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;

    let err = charge_gas(Uint(GasConstants.GAS_BASE));
    if (cast(err, felt) != 0) {
        return err;
    }

    let _blob_base_fee = calculate_blob_gas_price(evm.value.env.value.excess_blob_gas);

    tempvar blob_base_fee = U256(new U256Struct(_blob_base_fee.value, 0));
    let stack = evm.value.stack;
    with stack {
        let err = push(blob_base_fee);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);

    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Load input data from the current environment's call data
func calldataload{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;

    // STACK
    let stack = evm.value.stack;
    with stack {
        let (offset, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // GAS
    let err = charge_gas(Uint(GasConstants.GAS_VERY_LOW));
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    let calldata = evm.value.message.value.data;
    let data = buffer_read(calldata, offset, U256(new U256Struct(32, 0)));
    let data_u256 = Helpers.bytes_to_uint256(data.value.len, data.value.data);
    tempvar data_to_push = U256(new U256Struct(data_u256.low, data_u256.high));

    with stack {
        let err = push(data_to_push);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Copy a portion of the input data in current environment to memory
func calldatacopy{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;

    // STACK
    let stack = evm.value.stack;
    with stack {
        let (memory_start_index, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (data_start_index, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
        let (size, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // GAS
    // OutOfGasError if size > 2**128
    if (size.value.high != 0) {
        tempvar err = new ExceptionalHalt(OutOfGasError);
        return err;
    }

    let ceil32_size = ceil32(Uint(size.value.low));
    let (words, _) = divmod(ceil32_size.value, 32);
    let copy_gas_cost = GasConstants.GAS_COPY * words;

    // Calculate memory expansion cost
    tempvar extensions_tuple = new TupleU256U256(new TupleU256U256Struct(memory_start_index, size));
    tempvar extensions_list = ListTupleU256U256(new ListTupleU256U256Struct(extensions_tuple, 1));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, extensions_list);

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
        let value = buffer_read(evm.value.message.value.data, data_start_index, size);
        memory_write(memory_start_index, value);
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack_memory(Uint(evm.value.pc.value + 1), stack, memory);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

func calldatasize{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    // No stack input
    let stack = evm.value.stack;
    // GAS
    let err = charge_gas(Uint(GasConstants.GAS_BASE));
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    let calldata_len = evm.value.message.value.data.value.len;
    with stack {
        let err = push(U256(new U256Struct(calldata_len, 0)));
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);

    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

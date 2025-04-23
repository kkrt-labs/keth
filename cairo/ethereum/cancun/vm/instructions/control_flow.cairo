from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, PoseidonBuiltin, ModBuiltin
from starkware.cairo.common.dict import DictAccess
from legacy.utils.dict import dict_read

from ethereum_types.numeric import (
    U256,
    U256Struct,
    Uint,
    bool,
    SetUint,
    SetUintStruct,
    SetUintDictAccess,
)

from ethereum.cancun.vm.evm_impl import Evm, EvmImpl
from ethereum.exceptions import EthereumException
from ethereum.cancun.vm.exceptions import InvalidJumpDestError
from ethereum.cancun.vm.gas import charge_gas, GasConstants
from ethereum.cancun.vm.stack import Stack, pop, push

from legacy.utils.dict import hashdict_read

// @notice Stop further execution of EVM code
func stop{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    // STACK

    // GAS
    // No gas charge for STOP

    // OPERATION
    EvmImpl.set_running(bool(FALSE));

    // PROGRAM COUNTER
    EvmImpl.set_pc(Uint(evm.value.pc.value + 1));
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Alter the program counter to the location specified by the top of the stack
func jump{
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
        let (jump_dest, err1) = pop();
        if (cast(err1, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err1;
        }
    }

    // GAS
    let err2 = charge_gas(Uint(GasConstants.GAS_MID));
    if (cast(err2, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err2;
    }

    // OPERATION
    if (jump_dest.value.high != 0) {
        EvmImpl.set_stack(stack);
        tempvar err = new EthereumException(InvalidJumpDestError);
        return err;
    }

    // Check if jump destination is valid by looking it up in valid_jump_destinations
    let valid_jump_destinations = evm.value.valid_jump_destinations;
    let is_valid_dest = set_uint_contains{set=valid_jump_destinations}(jump_dest.value.low);
    EvmImpl.set_valid_jump_destinations(valid_jump_destinations);

    if (is_valid_dest == FALSE) {
        EvmImpl.set_stack(stack);
        tempvar err = new EthereumException(InvalidJumpDestError);
        return err;
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(jump_dest.value.low), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Alter the program counter to the specified location if and only if a condition is true
func jumpi{
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
        let (jump_dest, err1) = pop();
        if (cast(err1, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err1;
        }
        let (condition, err2) = pop();
        if (cast(err2, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err2;
        }
    }

    // GAS
    let err3 = charge_gas(Uint(GasConstants.GAS_HIGH));
    if (cast(err3, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err3;
    }

    // OPERATION
    if (jump_dest.value.high != 0) {
        EvmImpl.set_stack(stack);
        tempvar err = new EthereumException(InvalidJumpDestError);
        return err;
    }

    if (condition.value.low == 0 and condition.value.high == 0) {
        // If condition is false, just increment PC
        EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
        let ok = cast(0, EthereumException*);
        return ok;
    }

    let valid_jump_destinations = evm.value.valid_jump_destinations;
    let is_valid_dest = set_uint_contains{set=valid_jump_destinations}(jump_dest.value.low);
    EvmImpl.set_valid_jump_destinations(valid_jump_destinations);

    if (is_valid_dest == FALSE) {
        EvmImpl.set_stack(stack);
        tempvar err = new EthereumException(InvalidJumpDestError);
        return err;
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(jump_dest.value.low), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Push the value of the program counter before the increment onto the stack
func pc{
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
    let err1 = charge_gas(Uint(GasConstants.GAS_BASE));
    if (cast(err1, felt) != 0) {
        return err1;
    }

    // OPERATION
    with stack {
        let err2 = push(U256(new U256Struct(evm.value.pc.value, 0)));
        if (cast(err2, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err2;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Push the amount of available gas onto the stack
func gas_left{
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
    let err1 = charge_gas(Uint(GasConstants.GAS_BASE));
    if (cast(err1, felt) != 0) {
        return err1;
    }

    // OPERATION
    with stack {
        let err2 = push(U256(new U256Struct(evm.value.gas_left.value, 0)));
        if (cast(err2, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err2;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Mark a valid destination for jumps
func jumpdest{
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

    // GAS
    let err = charge_gas(Uint(GasConstants.GAS_JUMPDEST));
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    // No operation needed, just a marker

    // PROGRAM COUNTER
    EvmImpl.set_pc(Uint(evm.value.pc.value + 1));
    let ok = cast(0, EthereumException*);
    return ok;
}

// Utils function, porting this to a module would incur a lot of refactoring due to circular imports
func set_uint_contains{range_check_ptr, set: SetUint}(key: felt) -> felt {
    alloc_locals;
    let dict_ptr = cast(set.value.dict_ptr, DictAccess*);
    let (value) = dict_read{dict_ptr=dict_ptr}(key);
    tempvar set = SetUint(
        new SetUintStruct(
            dict_ptr_start=set.value.dict_ptr_start, dict_ptr=cast(dict_ptr, SetUintDictAccess*)
        ),
    );
    return value;
}

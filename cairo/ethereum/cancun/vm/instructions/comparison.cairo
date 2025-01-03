from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.uint256 import uint256_eq, Uint256

from src.utils.uint256 import uint256_lt, uint256_signed_lt
from ethereum.cancun.vm.stack import Stack, pop, push
from ethereum.cancun.vm import Evm, EvmImpl
from ethereum.cancun.vm.exceptions import ExceptionalHalt
from ethereum_types.numeric import U256, U256Struct, Uint
from ethereum.cancun.vm.gas import charge_gas, GasConstants

// @notice Checks if the top element is less than the next top element
func less_than{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (x, err1) = pop();
        if (cast(err1, felt) != 0) {
            return err1;
        }
        let (y, err2) = pop();
        if (cast(err2, felt) != 0) {
            return err2;
        }
    }

    // GAS
    let err3 = charge_gas(Uint(GasConstants.GAS_VERY_LOW));
    if (cast(err3, felt) != 0) {
        return err3;
    }

    // OPERATION
    let (result) = uint256_lt([x.value], [y.value]);
    with stack {
        let err4 = push(U256(new U256Struct(result, 0)));
        if (cast(err4, felt) != 0) {
            return err4;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_stack(stack);
    EvmImpl.set_pc(Uint(evm.value.pc.value + 1));
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Checks if the top element is greater than the next top element
func greater_than{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (x, err1) = pop();
        if (cast(err1, felt) != 0) {
            return err1;
        }
        let (y, err2) = pop();
        if (cast(err2, felt) != 0) {
            return err2;
        }
    }

    // GAS
    let err3 = charge_gas(Uint(GasConstants.GAS_VERY_LOW));
    if (cast(err3, felt) != 0) {
        return err3;
    }

    // OPERATION
    let (result) = uint256_lt([y.value], [x.value]);
    with stack {
        let err4 = push(U256(new U256Struct(result, 0)));
        if (cast(err4, felt) != 0) {
            return err4;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_stack(stack);
    EvmImpl.set_pc(Uint(evm.value.pc.value + 1));
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Signed less-than comparison
func signed_less_than{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (x, err1) = pop();
        if (cast(err1, felt) != 0) {
            return err1;
        }
        let (y, err2) = pop();
        if (cast(err2, felt) != 0) {
            return err2;
        }
    }

    // GAS
    let err3 = charge_gas(Uint(GasConstants.GAS_VERY_LOW));
    if (cast(err3, felt) != 0) {
        return err3;
    }

    // OPERATION
    let (result) = uint256_signed_lt([x.value], [y.value]);
    with stack {
        let err4 = push(U256(new U256Struct(result, 0)));
        if (cast(err4, felt) != 0) {
            return err4;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_stack(stack);
    EvmImpl.set_pc(Uint(evm.value.pc.value + 1));
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Signed greater-than comparison
func signed_greater_than{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (x, err1) = pop();
        if (cast(err1, felt) != 0) {
            return err1;
        }
        let (y, err2) = pop();
        if (cast(err2, felt) != 0) {
            return err2;
        }
    }

    // GAS
    let err3 = charge_gas(Uint(GasConstants.GAS_VERY_LOW));
    if (cast(err3, felt) != 0) {
        return err3;
    }

    // OPERATION
    let (result) = uint256_signed_lt([y.value], [x.value]);
    with stack {
        let err4 = push(U256(new U256Struct(result, 0)));
        if (cast(err4, felt) != 0) {
            return err4;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_stack(stack);
    EvmImpl.set_pc(Uint(evm.value.pc.value + 1));
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Checks if the top element is equal to the next top element
func equal{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (x, err1) = pop();
        if (cast(err1, felt) != 0) {
            return err1;
        }
        let (y, err2) = pop();
        if (cast(err2, felt) != 0) {
            return err2;
        }
    }

    // GAS
    let err3 = charge_gas(Uint(GasConstants.GAS_VERY_LOW));
    if (cast(err3, felt) != 0) {
        return err3;
    }

    // OPERATION
    let (result) = uint256_eq([x.value], [y.value]);
    with stack {
        let err4 = push(U256(new U256Struct(result, 0)));
        if (cast(err4, felt) != 0) {
            return err4;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_stack(stack);
    EvmImpl.set_pc(Uint(evm.value.pc.value + 1));
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Checks if the top element is equal to zero
func is_zero{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (x, err1) = pop();
        if (cast(err1, felt) != 0) {
            return err1;
        }
    }

    // GAS
    let err2 = charge_gas(Uint(GasConstants.GAS_VERY_LOW));
    if (cast(err2, felt) != 0) {
        return err2;
    }

    // OPERATION
    let (result) = uint256_eq([x.value], Uint256(0, 0));
    with stack {
        let err3 = push(U256(new U256Struct(result, 0)));
        if (cast(err3, felt) != 0) {
            return err3;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_stack(stack);
    EvmImpl.set_pc(Uint(evm.value.pc.value + 1));
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

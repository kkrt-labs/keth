from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.uint256 import (
    uint256_and,
    uint256_not,
    uint256_or,
    uint256_shl,
    uint256_shr,
    uint256_xor,
    ALL_ONES,
    Uint256,
)

from src.utils.uint256 import uint256_lt
from ethereum.cancun.vm.stack import Stack, pop, push
from ethereum.cancun.vm import Evm, EvmImpl
from ethereum.cancun.vm.exceptions import ExceptionalHalt
from ethereum_types.numeric import U256, U256Struct, Uint
from ethereum.cancun.vm.gas import charge_gas, GasConstants

// @notice Performs bitwise AND operation on the top two stack elements
func bitwise_and{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, evm: Evm}() -> ExceptionalHalt* {
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
    let (result) = uint256_and([x.value], [y.value]);
    with stack {
        let err4 = push(U256(new U256Struct(result.low, result.high)));
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

// @notice Performs bitwise OR operation on the top two stack elements
func bitwise_or{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, evm: Evm}() -> ExceptionalHalt* {
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
    let (result) = uint256_or([x.value], [y.value]);
    with stack {
        let err4 = push(U256(new U256Struct(result.low, result.high)));
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

// @notice Performs bitwise XOR operation on the top two stack elements
func bitwise_xor{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, evm: Evm}() -> ExceptionalHalt* {
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
    let (result) = uint256_xor([x.value], [y.value]);
    with stack {
        let err4 = push(U256(new U256Struct(result.low, result.high)));
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

// @notice Performs bitwise NOT operation on the top stack element
func bitwise_not{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, evm: Evm}() -> ExceptionalHalt* {
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
    let (result) = uint256_not([x.value]);
    with stack {
        let err3 = push(U256(new U256Struct(result.low, result.high)));
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

// @notice Returns the byte at position n in x, where n is the position from the most significant byte
func get_byte{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (n, err1) = pop();
        if (cast(err1, felt) != 0) {
            return err1;
        }
        let (x, err2) = pop();
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
    let (is_valid_pos) = uint256_lt([n.value], U256Struct(32, 0));
    if (is_valid_pos == 0) {
        with stack {
            let err4 = push(U256(new U256Struct(0, 0)));
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

    tempvar right = U256Struct(248 - n.value.low * 8, 0);
    let (shift_right) = uint256_shr([x.value], right);
    let (result) = uint256_and(shift_right, U256Struct(0xFF, 0));
    with stack {
        let err4 = push(U256(new U256Struct(result.low, result.high)));
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

// @notice Left shift operation
func bitwise_shl{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (shift, err1) = pop();
        if (cast(err1, felt) != 0) {
            return err1;
        }
        let (value, err2) = pop();
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
    let (result) = uint256_shl([value.value], [shift.value]);
    with stack {
        let err4 = push(U256(new U256Struct(result.low, result.high)));
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

// @notice Right shift operation
func bitwise_shr{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (shift, err1) = pop();
        if (cast(err1, felt) != 0) {
            return err1;
        }
        let (value, err2) = pop();
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
    let (result) = uint256_shr([value.value], [shift.value]);
    with stack {
        let err4 = push(U256(new U256Struct(result.low, result.high)));
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

// @notice Sign extend operation
func bitwise_sar{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (shift, err1) = pop();
        if (cast(err1, felt) != 0) {
            return err1;
        }

        let (value, err2) = pop();
        if (cast(err2, felt) != 0) {
            return err2;
        }
    }

    // GAS
    let err3 = charge_gas(Uint(GasConstants.GAS_VERY_LOW));
    if (cast(err3, felt) != 0) {
        return err3;
    }

    // In C, SAR would be something like that (on a 4 bytes int):
    // ```
    // int sign = -((unsigned) x >> 31);
    // int sar = (sign^x) >> n ^ sign;
    // ```
    // This is the cairo adaptation
    // (unsigned) x >> 31 : extract the left-most bit (i.e. the sign).
    let (_sign) = uint256_shr([value.value], Uint256(255, 0));

    // Declare low and high as tempvar because we can't declare a Uint256 as tempvar.
    tempvar low;
    tempvar high;
    if (_sign.low == 0) {
        // If sign is positive, set it to 0.
        low = 0;
        high = 0;
    } else {
        // If sign is negative, set the number to -1.
        low = ALL_ONES;
        high = ALL_ONES;
    }

    // Rebuild the `sign` variable from `low` and `high`.
    let sign = Uint256(low, high);

    // `sign ^ x`
    let (step1) = uint256_xor(sign, [value.value]);
    // `sign ^ x >> n`
    let (step2) = uint256_shr(step1, [shift.value]);
    // `sign & x >> n ^ sign`
    let (result) = uint256_xor(step2, sign);

    with stack {
        let err4 = push(U256(new U256Struct(result.low, result.high)));
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

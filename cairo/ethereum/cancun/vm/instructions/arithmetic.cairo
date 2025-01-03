from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.bool import FALSE
from starkware.cairo.common.uint256 import (
    uint256_add,
    uint256_sub,
    uint256_mul,
    uint256_unsigned_div_rem,
    uint256_signed_div_rem,
)

from src.utils.uint256 import uint256_eq, uint256_fast_exp, uint256_signextend
from src.utils.utils import Helpers
from ethereum.cancun.vm.stack import Stack, pop, push
from ethereum.cancun.vm import Evm, EvmImpl
from ethereum.cancun.vm.exceptions import ExceptionalHalt
from ethereum_types.numeric import U256, U256Struct, Uint
from ethereum.cancun.vm.gas import charge_gas, GasConstants

// @title Arithmetic operations for the EVM
// @notice Implements arithmetic operations like add, sub, mul, div, etc.

// @notice Adds the top two elements of the stack together
func add{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
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
    let (result, _) = uint256_add([x.value], [y.value]);
    with stack {
        let err4 = push(U256(new U256Struct(result.low, result.high)));
        if (cast(err4, felt) != 0) {
            return err4;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc(Uint(evm.value.pc.value + 1));
    EvmImpl.set_stack(stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Subtracts the top two elements of the stack
func sub{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
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
    let (result) = uint256_sub([x.value], [y.value]);
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

// @notice Multiplies the top two elements of the stack
func mul{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
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
    let err3 = charge_gas(Uint(GasConstants.GAS_LOW));
    if (cast(err3, felt) != 0) {
        return err3;
    }

    // OPERATION
    let (result, _) = uint256_mul([x.value], [y.value]);
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

// @notice Integer division of the top two elements of the stack
func div{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
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
    let err3 = charge_gas(Uint(GasConstants.GAS_LOW));
    if (cast(err3, felt) != 0) {
        return err3;
    }

    // OPERATION
    with stack {
        let (is_zero) = uint256_eq([y.value], U256Struct(0, 0));
        if (is_zero != 0) {
            let err4 = push(U256(new U256Struct(0, 0)));
            if (cast(err4, felt) != 0) {
                return err4;
            }
            tempvar range_check_ptr = range_check_ptr;
        } else {
            let (result, _) = uint256_unsigned_div_rem([x.value], [y.value]);
            let err4 = push(U256(new U256Struct(result.low, result.high)));
            if (cast(err4, felt) != 0) {
                return err4;
            }
            tempvar range_check_ptr = range_check_ptr;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_stack(stack);
    EvmImpl.set_pc(Uint(evm.value.pc.value + 1));
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Signed integer division of the top two elements of the stack
func sdiv{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
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
    let err3 = charge_gas(Uint(GasConstants.GAS_LOW));
    if (cast(err3, felt) != 0) {
        return err3;
    }

    // OPERATION
    let (result, _) = uint256_signed_div_rem([x.value], [y.value]);
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

// @notice Modulo remainder of the top two elements of the stack
func mod{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
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
    let err3 = charge_gas(Uint(GasConstants.GAS_LOW));
    if (cast(err3, felt) != 0) {
        return err3;
    }

    // OPERATION
    with stack {
        let (is_zero) = uint256_eq([y.value], U256Struct(0, 0));
        if (is_zero != 0) {
            let err4 = push(U256(new U256Struct(0, 0)));
            if (cast(err4, felt) != 0) {
                return err4;
            }
            tempvar range_check_ptr = range_check_ptr;
        } else {
            let (_, remainder) = uint256_unsigned_div_rem([x.value], [y.value]);
            let err4 = push(U256(new U256Struct(remainder.low, remainder.high)));
            if (cast(err4, felt) != 0) {
                return err4;
            }
            tempvar range_check_ptr = range_check_ptr;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_stack(stack);
    EvmImpl.set_pc(Uint(evm.value.pc.value + 1));
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Signed modulo remainder of the top two elements of the stack
func smod{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
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
    let err3 = charge_gas(Uint(GasConstants.GAS_LOW));
    if (cast(err3, felt) != 0) {
        return err3;
    }

    // OPERATION
    with stack {
        let (is_zero) = uint256_eq([y.value], U256Struct(0, 0));
        if (is_zero != 0) {
            let err4 = push(U256(new U256Struct(0, 0)));
            if (cast(err4, felt) != 0) {
                return err4;
            }
            tempvar range_check_ptr = range_check_ptr;
        } else {
            let (_, remainder) = uint256_signed_div_rem([x.value], [y.value]);
            let err4 = push(U256(new U256Struct(remainder.low, remainder.high)));
            if (cast(err4, felt) != 0) {
                return err4;
            }
            tempvar range_check_ptr = range_check_ptr;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_stack(stack);
    EvmImpl.set_pc(Uint(evm.value.pc.value + 1));
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Addition modulo of three elements on the stack
func addmod{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
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
        let (n, err3) = pop();
        if (cast(err3, felt) != 0) {
            return err3;
        }
    }

    // GAS
    let err4 = charge_gas(Uint(GasConstants.GAS_MID));
    if (cast(err4, felt) != 0) {
        return err4;
    }

    // OPERATION
    with stack {
        let (is_zero) = uint256_eq([n.value], U256Struct(0, 0));
        if (is_zero != 0) {
            let err5 = push(U256(new U256Struct(0, 0)));
            if (cast(err5, felt) != 0) {
                return err5;
            }
            tempvar range_check_ptr = range_check_ptr;
        } else {
            let (sum, _) = uint256_add([x.value], [y.value]);
            let (_, remainder) = uint256_unsigned_div_rem(sum, [n.value]);
            let err5 = push(U256(new U256Struct(remainder.low, remainder.high)));
            if (cast(err5, felt) != 0) {
                return err5;
            }
            tempvar range_check_ptr = range_check_ptr;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_stack(stack);
    EvmImpl.set_pc(Uint(evm.value.pc.value + 1));
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Multiplication modulo of three elements on the stack
func mulmod{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
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
        let (n, err3) = pop();
        if (cast(err3, felt) != 0) {
            return err3;
        }
    }

    // GAS
    let err4 = charge_gas(Uint(GasConstants.GAS_MID));
    if (cast(err4, felt) != 0) {
        return err4;
    }

    // OPERATION
    with stack {
        let (is_zero) = uint256_eq([n.value], U256Struct(0, 0));
        if (is_zero != 0) {
            let err5 = push(U256(new U256Struct(0, 0)));
            if (cast(err5, felt) != 0) {
                return err5;
            }
            tempvar range_check_ptr = range_check_ptr;
        } else {
            let (product, _) = uint256_mul([x.value], [y.value]);
            let (_, remainder) = uint256_unsigned_div_rem(product, [n.value]);
            let err5 = push(U256(new U256Struct(remainder.low, remainder.high)));
            if (cast(err5, felt) != 0) {
                return err5;
            }
            tempvar range_check_ptr = range_check_ptr;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_stack(stack);
    EvmImpl.set_pc(Uint(evm.value.pc.value + 1));
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

// @notice Exponential operation of the top 2 elements
func exp{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (base, err1) = pop();
        if (cast(err1, felt) != 0) {
            return err1;
        }
        let (exponent, err2) = pop();
        if (cast(err2, felt) != 0) {
            return err2;
        }
    }

    // GAS
    // Calculate bytes used for gas cost
    local bytes_used: felt;
    if (exponent.value.high == 0) {
        let bytes_used_low = Helpers.bytes_used_128(exponent.value.low);
        assert bytes_used = bytes_used_low;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        let bytes_used_high = Helpers.bytes_used_128(exponent.value.high);
        assert bytes_used = bytes_used_high + 16;
        tempvar range_check_ptr = range_check_ptr;
    }

    let gas_cost = Uint(
        GasConstants.GAS_EXPONENTIATION + GasConstants.GAS_EXPONENTIATION_PER_BYTE * bytes_used
    );
    let err3 = charge_gas(gas_cost);
    if (cast(err3, felt) != 0) {
        return err3;
    }

    // OPERATION
    let result = uint256_fast_exp([base.value], [exponent.value]);
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
func signextend{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (byte_num, err1) = pop();
        if (cast(err1, felt) != 0) {
            return err1;
        }
        let (value, err2) = pop();
        if (cast(err2, felt) != 0) {
            return err2;
        }
    }

    // GAS
    let err3 = charge_gas(Uint(GasConstants.GAS_LOW));
    if (cast(err3, felt) != 0) {
        return err3;
    }

    // OPERATION
    let result = uint256_signextend([value.value], [byte_num.value]);
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

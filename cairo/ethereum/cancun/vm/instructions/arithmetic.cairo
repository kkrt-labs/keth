from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin, PoseidonBuiltin
from starkware.cairo.common.uint256 import uint256_mul, ALL_ONES, uint256_lt

from src.utils.uint256 import (
    uint256_eq,
    uint256_fast_exp,
    uint256_signextend,
    uint256_sub,
    uint256_add,
    uint256_unsigned_div_rem,
    uint256_signed_div_rem,
    uint256_mul_div_mod,
)
from src.utils.utils import Helpers
from ethereum.cancun.vm.stack import Stack, pop, push
from ethereum.cancun.vm import Evm, EvmImpl
from ethereum.exceptions import EthereumException
from ethereum_types.numeric import U256, U256Struct, Uint
from ethereum.cancun.vm.gas import charge_gas, GasConstants

// @title Arithmetic operations for the EVM
// @notice Implements arithmetic operations like add, sub, mul, div, etc.

// @notice Adds the top two elements of the stack together
func add{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (x, err1) = pop();
        if (cast(err1, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err1;
        }
        let (y, err2) = pop();
        if (cast(err2, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err2;
        }
    }

    // GAS
    let err3 = charge_gas(Uint(GasConstants.GAS_VERY_LOW));
    if (cast(err3, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err3;
    }

    // OPERATION
    let (result, _) = uint256_add([x.value], [y.value]);
    // cannot fail with StackOverflowError, 2 elements were popped
    push{stack=stack}(U256(new U256Struct(result.low, result.high)));

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Subtracts the top two elements of the stack
func sub{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (x, err1) = pop();
        if (cast(err1, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err1;
        }
        let (y, err2) = pop();
        if (cast(err2, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err2;
        }
    }

    // GAS
    let err3 = charge_gas(Uint(GasConstants.GAS_VERY_LOW));
    if (cast(err3, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err3;
    }

    // OPERATION
    let (result) = uint256_sub([x.value], [y.value]);
    // cannot fail with StackOverflowError, 2 elements were popped
    push{stack=stack}(U256(new U256Struct(result.low, result.high)));

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Multiplies the top two elements of the stack
func mul{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (x, err1) = pop();
        if (cast(err1, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err1;
        }
        let (y, err2) = pop();
        if (cast(err2, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err2;
        }
    }

    // GAS
    let err3 = charge_gas(Uint(GasConstants.GAS_LOW));
    if (cast(err3, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err3;
    }

    // OPERATION
    let (result, _) = uint256_mul([x.value], [y.value]);
    // cannot fail with StackOverflowError, 2 elements were popped
    push{stack=stack}(U256(new U256Struct(result.low, result.high)));

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Integer division of the top two elements of the stack
func div{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (x, err1) = pop();
        if (cast(err1, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err1;
        }
        let (y, err2) = pop();
        if (cast(err2, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err2;
        }
    }

    // GAS
    let err3 = charge_gas(Uint(GasConstants.GAS_LOW));
    if (cast(err3, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err3;
    }

    // OPERATION
    with stack {
        let (is_zero) = uint256_eq([y.value], U256Struct(0, 0));
        if (is_zero != 0) {
            // cannot fail with StackOverflowError, 2 elements were popped
            push{stack=stack}(U256(new U256Struct(0, 0)));
            tempvar range_check_ptr = range_check_ptr;
        } else {
            let (result, _) = uint256_unsigned_div_rem([x.value], [y.value]);
            // cannot fail with StackOverflowError, 2 elements were popped
            push{stack=stack}(U256(new U256Struct(result.low, result.high)));
            tempvar range_check_ptr = range_check_ptr;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Signed integer division of the top two elements of the stack
func sdiv{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (x, err1) = pop();
        if (cast(err1, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err1;
        }
        let (y, err2) = pop();
        if (cast(err2, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err2;
        }
    }

    // GAS
    let err3 = charge_gas(Uint(GasConstants.GAS_LOW));
    if (cast(err3, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err3;
    }

    // OPERATION
    let (result, _) = uint256_signed_div_rem([x.value], [y.value]);
    // cannot fail with StackOverflowError, 2 elements were popped
    push{stack=stack}(U256(new U256Struct(result.low, result.high)));

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Modulo remainder of the top two elements of the stack
func mod{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (x, err1) = pop();
        if (cast(err1, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err1;
        }
        let (y, err2) = pop();
        if (cast(err2, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err2;
        }
    }

    // GAS
    let err3 = charge_gas(Uint(GasConstants.GAS_LOW));
    if (cast(err3, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err3;
    }

    // OPERATION
    with stack {
        let (is_zero) = uint256_eq([y.value], U256Struct(0, 0));
        if (is_zero != 0) {
            // cannot fail with StackOverflowError, 2 elements were popped
            push{stack=stack}(U256(new U256Struct(0, 0)));
            tempvar range_check_ptr = range_check_ptr;
        } else {
            let (_, remainder) = uint256_unsigned_div_rem([x.value], [y.value]);
            // cannot fail with StackOverflowError, 2 elements were popped
            push{stack=stack}(U256(new U256Struct(remainder.low, remainder.high)));
            tempvar range_check_ptr = range_check_ptr;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Signed modulo remainder of the top two elements of the stack
func smod{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (x, err1) = pop();
        if (cast(err1, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err1;
        }
        let (y, err2) = pop();
        if (cast(err2, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err2;
        }
    }

    // GAS
    let err3 = charge_gas(Uint(GasConstants.GAS_LOW));
    if (cast(err3, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err3;
    }

    // OPERATION
    with stack {
        let (is_zero) = uint256_eq([y.value], U256Struct(0, 0));
        if (is_zero != 0) {
            // cannot fail with StackOverflowError, 2 elements were popped
            push{stack=stack}(U256(new U256Struct(0, 0)));
            tempvar range_check_ptr = range_check_ptr;
        } else {
            let (_, remainder) = uint256_signed_div_rem([x.value], [y.value]);
            // cannot fail with StackOverflowError, 2 elements were popped
            push{stack=stack}(U256(new U256Struct(remainder.low, remainder.high)));
            tempvar range_check_ptr = range_check_ptr;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Addition modulo of three elements on the stack
func addmod{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (a, err1) = pop();
        if (cast(err1, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err1;
        }
        let (b, err2) = pop();
        if (cast(err2, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err2;
        }
        let (n, err3) = pop();
        if (cast(err3, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err3;
        }
    }

    // GAS
    let err4 = charge_gas(Uint(GasConstants.GAS_MID));
    if (cast(err4, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err4;
    }

    // OPERATION
    let (is_zero) = uint256_eq([n.value], U256Struct(0, 0));
    if (is_zero != 0) {
        // cannot fail with StackOverflowError, 3 elements were popped
        push{stack=stack}(U256(new U256Struct(0, 0)));
        // early return if n is zero
        EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
        let ok = cast(0, EthereumException*);
        return ok;
    }

    // (a + b) mod n  = (a mod n + b mod n) mod n
    let (_, x) = uint256_unsigned_div_rem([a.value], [n.value]);
    let (_, y) = uint256_unsigned_div_rem([b.value], [n.value]);
    // x, y in range [0, n-1] thus:
    // if x + y < n then x + y mod n = x + y
    // if x + y >= n then x + y mod n = x + y - n
    let (sum, carry) = uint256_add(x, y);
    if (carry != 0) {
        // result = (2**256) - (n - overflown_sum)
        // <=> result = (2**256 - 1) - (n - overflown_sum - 1)
        // as n > overflown_sum we can't have an underflow
        tempvar max_u256 = U256Struct(ALL_ONES, ALL_ONES);
        let (overflown_part) = uint256_sub([n.value], sum);
        let (to_remove) = uint256_sub(overflown_part, U256Struct(1, 0));
        let (result) = uint256_sub(max_u256, to_remove);
        // cannot fail with StackOverflowError, 3 elements were popped
        push{stack=stack}(U256(new U256Struct(result.low, result.high)));
        EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
        let ok = cast(0, EthereumException*);
        return ok;
    }

    let (is_sum_lt_n) = uint256_lt(sum, [n.value]);
    if (is_sum_lt_n != 0) {
        // cannot fail with StackOverflowError, 3 elements were popped
        push{stack=stack}(U256(new U256Struct(sum.low, sum.high)));
        EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
        let ok = cast(0, EthereumException*);
        return ok;
    }

    let (result) = uint256_sub(sum, [n.value]);
    // cannot fail with StackOverflowError, 3 elements were popped
    push{stack=stack}(U256(new U256Struct(result.low, result.high)));
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Multiplication modulo of three elements on the stack
func mulmod{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (a, err1) = pop();
        if (cast(err1, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err1;
        }
        let (b, err2) = pop();
        if (cast(err2, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err2;
        }
        let (n, err3) = pop();
        if (cast(err3, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err3;
        }
    }

    // GAS
    let err4 = charge_gas(Uint(GasConstants.GAS_MID));
    if (cast(err4, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err4;
    }

    // OPERATION
    let (is_zero) = uint256_eq([n.value], U256Struct(0, 0));
    if (is_zero != 0) {
        // cannot fail with StackOverflowError, 3 elements were popped
        push{stack=stack}(U256(new U256Struct(0, 0)));
        EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
        let ok = cast(0, EthereumException*);
        return ok;
    }

    let (_, _, result) = uint256_mul_div_mod([a.value], [b.value], [n.value]);
    // cannot fail with StackOverflowError, 3 elements were popped
    push{stack=stack}(U256(new U256Struct(result.low, result.high)));

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Exponential operation of the top 2 elements
func exp{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (base, err1) = pop();
        if (cast(err1, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err1;
        }
        let (exponent, err2) = pop();
        if (cast(err2, felt) != 0) {
            EvmImpl.set_stack(stack);
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
        EvmImpl.set_stack(stack);
        return err3;
    }

    // OPERATION
    let result = uint256_fast_exp([base.value], [exponent.value]);
    // cannot fail with StackOverflowError, 2 elements were popped
    push{stack=stack}(U256(new U256Struct(result.low, result.high)));

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Sign extend operation
func signextend{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (byte_num, err1) = pop();
        if (cast(err1, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err1;
        }
        let (value, err2) = pop();
        if (cast(err2, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err2;
        }
    }

    // GAS
    let err3 = charge_gas(Uint(GasConstants.GAS_LOW));
    if (cast(err3, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err3;
    }

    // OPERATION
    let result = uint256_signextend([value.value], [byte_num.value]);
    // cannot fail with StackOverflowError, 2 elements were popped
    push{stack=stack}(U256(new U256Struct(result.low, result.high)));

    // PROGRAM COUNTER
    let ok = cast(0, EthereumException*);
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    return ok;
}

from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.dict import DictAccess, dict_read, dict_write

from ethereum.cancun.vm.stack import push, StackDictAccess, Stack, StackStruct
from ethereum.cancun.vm import Evm, EvmImpl
from ethereum.cancun.vm.exceptions import ExceptionalHalt, StackUnderflowError
from ethereum.cancun.vm.gas import charge_gas, GasConstants
from ethereum_types.numeric import Uint, U256, U256Struct
from ethereum.utils.numeric import is_zero
from ethereum.cancun.vm.memory import buffer_read
from src.utils.utils import Helpers

// @notice Pushes a value to the stack
func push_n{range_check_ptr, evm: Evm}(num_bytes: Uint) -> ExceptionalHalt* {
    alloc_locals;

    let push0 = is_zero(num_bytes.value);
    let err = charge_gas(
        Uint(GasConstants.GAS_BASE * push0 + GasConstants.GAS_VERY_LOW * (1 - push0))
    );
    if (cast(err, felt) != 0) {
        return err;
    }

    let code = evm.value.code;
    tempvar start_position = U256(new U256Struct(evm.value.pc.value + 1, 0));
    // @dev: assumption that size is <= 32
    tempvar size = U256(new U256Struct(num_bytes.value, 0));
    let _data = buffer_read(code, start_position, size);
    let data = Helpers.bytes_to_uint256(num_bytes.value, _data.value.data);
    tempvar data_to_push = U256(new U256Struct(data.low, data.high));

    // STACK
    let stack = evm.value.stack;
    with stack {
        let err = push(data_to_push);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1 + num_bytes.value), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

func swap_n{range_check_ptr, evm: Evm}(n: Uint) -> ExceptionalHalt* {
    let err = charge_gas(Uint(GasConstants.GAS_VERY_LOW));
    if (cast(err, felt) != 0) {
        return err;
    }

    let stack = evm.value.stack;
    let len = stack.value.len;
    let stack_underflow = is_le(len, n.value);
    if (stack_underflow != 0) {
        tempvar err = new ExceptionalHalt(StackUnderflowError);
        return err;
    }

    let dict_ptr = cast(stack.value.dict_ptr, DictAccess*);
    with dict_ptr {
        let (stack_top) = dict_read(len - 1);
        let (swap_with) = dict_read(len - n.value - 1);
        dict_write(len - n.value - 1, stack_top);
        dict_write(len - 1, swap_with);
    }
    let new_dict_ptr = cast(dict_ptr, StackDictAccess*);
    tempvar stack = Stack(new StackStruct(stack.value.dict_ptr_start, new_dict_ptr, len));

    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

func dup_n{range_check_ptr, evm: Evm}(item_number: Uint) -> ExceptionalHalt* {
    alloc_locals;
    let err = charge_gas(Uint(GasConstants.GAS_VERY_LOW));
    if (cast(err, felt) != 0) {
        return err;
    }

    let stack = evm.value.stack;
    let len = stack.value.len;
    let stack_underflow = is_le(len, item_number.value);
    if (stack_underflow != 0) {
        tempvar err = new ExceptionalHalt(StackUnderflowError);
        return err;
    }

    let dict_ptr = cast(stack.value.dict_ptr, DictAccess*);
    with dict_ptr {
        let (value_to_dup) = dict_read(len - 1 - item_number.value);
    }
    let new_dict_ptr = cast(dict_ptr, StackDictAccess*);
    tempvar stack = Stack(new StackStruct(stack.value.dict_ptr_start, new_dict_ptr, len));

    tempvar value_to_push = U256(cast(value_to_dup, U256Struct*));
    with stack {
        let err = push(value_to_push);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}

func push0{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(0));
}
func push1{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(1));
}
func push2{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(2));
}
func push3{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(3));
}
func push4{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(4));
}
func push5{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(5));
}
func push6{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(6));
}
func push7{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(7));
}
func push8{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(8));
}
func push9{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(9));
}
func push10{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(10));
}
func push11{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(11));
}
func push12{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(12));
}
func push13{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(13));
}
func push14{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(14));
}
func push15{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(15));
}
func push16{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(16));
}
func push17{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(17));
}
func push18{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(18));
}
func push19{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(19));
}
func push20{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(20));
}
func push21{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(21));
}
func push22{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(22));
}
func push23{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(23));
}
func push24{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(24));
}
func push25{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(25));
}
func push26{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(26));
}
func push27{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(27));
}
func push28{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(28));
}
func push29{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(29));
}
func push30{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(30));
}
func push31{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(31));
}
func push32{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return push_n{evm=evm}(Uint(32));
}

func swap1{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return swap_n{evm=evm}(Uint(1));
}
func swap2{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return swap_n{evm=evm}(Uint(2));
}
func swap3{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return swap_n{evm=evm}(Uint(3));
}
func swap4{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return swap_n{evm=evm}(Uint(4));
}
func swap5{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return swap_n{evm=evm}(Uint(5));
}
func swap6{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return swap_n{evm=evm}(Uint(6));
}
func swap7{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return swap_n{evm=evm}(Uint(7));
}
func swap8{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return swap_n{evm=evm}(Uint(8));
}
func swap9{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return swap_n{evm=evm}(Uint(9));
}
func swap10{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return swap_n{evm=evm}(Uint(10));
}
func swap11{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return swap_n{evm=evm}(Uint(11));
}
func swap12{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return swap_n{evm=evm}(Uint(12));
}
func swap13{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return swap_n{evm=evm}(Uint(13));
}
func swap14{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return swap_n{evm=evm}(Uint(14));
}
func swap15{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return swap_n{evm=evm}(Uint(15));
}
func swap16{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return swap_n{evm=evm}(Uint(16));
}

func dup1{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return dup_n{evm=evm}(Uint(0));
}
func dup2{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return dup_n{evm=evm}(Uint(1));
}
func dup3{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return dup_n{evm=evm}(Uint(2));
}
func dup4{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return dup_n{evm=evm}(Uint(3));
}
func dup5{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return dup_n{evm=evm}(Uint(4));
}
func dup6{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return dup_n{evm=evm}(Uint(5));
}
func dup7{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return dup_n{evm=evm}(Uint(6));
}
func dup8{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return dup_n{evm=evm}(Uint(7));
}
func dup9{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return dup_n{evm=evm}(Uint(8));
}
func dup10{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return dup_n{evm=evm}(Uint(9));
}
func dup11{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return dup_n{evm=evm}(Uint(10));
}
func dup12{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return dup_n{evm=evm}(Uint(11));
}
func dup13{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return dup_n{evm=evm}(Uint(12));
}
func dup14{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return dup_n{evm=evm}(Uint(13));
}
func dup15{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return dup_n{evm=evm}(Uint(14));
}
func dup16{range_check_ptr, evm: Evm}() -> ExceptionalHalt* {
    return dup_n{evm=evm}(Uint(15));
}

from ethereum.cancun.vm.stack import push
from ethereum.cancun.vm import Evm, EvmImpl
from ethereum.cancun.vm.exceptions import ExceptionalHalt
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
    // @dev: assumption that size is less than 32
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

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

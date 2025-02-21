from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin, PoseidonBuiltin
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.dict import DictAccess
from legacy.utils.dict import dict_read, dict_write

from ethereum.cancun.vm.stack import push, StackDictAccess, Stack, StackStruct, pop as stack_pop
from ethereum.cancun.vm.evm_impl import Evm, EvmImpl
from ethereum.exceptions import EthereumException
from ethereum.cancun.vm.exceptions import StackUnderflowError
from ethereum.cancun.vm.gas import charge_gas, GasConstants
from ethereum_types.numeric import Uint, U256, U256Struct
from ethereum.cancun.vm.memory import buffer_read
from legacy.utils.utils import Helpers

from cairo_core.comparison import is_zero

// @notice Pushes a value to the stack
func push_n{range_check_ptr, evm: Evm}(num_bytes: Uint) -> EthereumException* {
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
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1 + num_bytes.value), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

func swap_n{range_check_ptr, evm: Evm}(n: Uint) -> EthereumException* {
    let err = charge_gas(Uint(GasConstants.GAS_VERY_LOW));
    if (cast(err, felt) != 0) {
        return err;
    }

    let stack = evm.value.stack;
    let len = stack.value.len;
    let stack_underflow = is_le(len, n.value);
    if (stack_underflow != 0) {
        tempvar err = new EthereumException(StackUnderflowError);
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
    let ok = cast(0, EthereumException*);
    return ok;
}

func dup_n{range_check_ptr, evm: Evm}(item_number: Uint) -> EthereumException* {
    alloc_locals;
    let err = charge_gas(Uint(GasConstants.GAS_VERY_LOW));
    if (cast(err, felt) != 0) {
        return err;
    }

    let stack = evm.value.stack;
    let len = stack.value.len;
    let stack_underflow = is_le(len, item_number.value);
    if (stack_underflow != 0) {
        tempvar err = new EthereumException(StackUnderflowError);
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
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

func pop{
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
        let (value, err) = stack_pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    // GAS
    let err = charge_gas(Uint(GasConstants.GAS_BASE));
    if (cast(err, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err;
    }

    // PROGRAM COUNTER
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

func push0{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(0));
    return res;
}
func push1{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(1));
    return res;
}
func push2{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(2));
    return res;
}
func push3{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(3));
    return res;
}
func push4{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(4));
    return res;
}
func push5{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(5));
    return res;
}
func push6{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(6));
    return res;
}
func push7{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(7));
    return res;
}
func push8{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(8));
    return res;
}
func push9{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(9));
    return res;
}
func push10{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(10));
    return res;
}
func push11{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(11));
    return res;
}
func push12{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(12));
    return res;
}
func push13{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(13));
    return res;
}
func push14{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(14));
    return res;
}
func push15{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(15));
    return res;
}
func push16{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(16));
    return res;
}
func push17{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(17));
    return res;
}
func push18{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(18));
    return res;
}
func push19{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(19));
    return res;
}
func push20{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(20));
    return res;
}
func push21{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(21));
    return res;
}
func push22{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(22));
    return res;
}
func push23{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(23));
    return res;
}
func push24{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(24));
    return res;
}
func push25{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(25));
    return res;
}
func push26{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(26));
    return res;
}
func push27{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(27));
    return res;
}
func push28{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(28));
    return res;
}
func push29{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(29));
    return res;
}
func push30{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(30));
    return res;
}
func push31{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(31));
    return res;
}
func push32{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = push_n(Uint(32));
    return res;
}

func swap1{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = swap_n(Uint(1));
    return res;
}
func swap2{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = swap_n(Uint(2));
    return res;
}
func swap3{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = swap_n(Uint(3));
    return res;
}
func swap4{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = swap_n(Uint(4));
    return res;
}
func swap5{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = swap_n(Uint(5));
    return res;
}
func swap6{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = swap_n(Uint(6));
    return res;
}
func swap7{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = swap_n(Uint(7));
    return res;
}
func swap8{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = swap_n(Uint(8));
    return res;
}
func swap9{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = swap_n(Uint(9));
    return res;
}
func swap10{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = swap_n(Uint(10));
    return res;
}
func swap11{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = swap_n(Uint(11));
    return res;
}
func swap12{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = swap_n(Uint(12));
    return res;
}
func swap13{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = swap_n(Uint(13));
    return res;
}
func swap14{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = swap_n(Uint(14));
    return res;
}
func swap15{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = swap_n(Uint(15));
    return res;
}
func swap16{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = swap_n(Uint(16));
    return res;
}

func dup1{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = dup_n(Uint(0));
    return res;
}
func dup2{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = dup_n(Uint(1));
    return res;
}
func dup3{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = dup_n(Uint(2));
    return res;
}
func dup4{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = dup_n(Uint(3));
    return res;
}
func dup5{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = dup_n(Uint(4));
    return res;
}
func dup6{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = dup_n(Uint(5));
    return res;
}
func dup7{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = dup_n(Uint(6));
    return res;
}
func dup8{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = dup_n(Uint(7));
    return res;
}
func dup9{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = dup_n(Uint(8));
    return res;
}
func dup10{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = dup_n(Uint(9));
    return res;
}
func dup11{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = dup_n(Uint(10));
    return res;
}
func dup12{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = dup_n(Uint(11));
    return res;
}
func dup13{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = dup_n(Uint(12));
    return res;
}
func dup14{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = dup_n(Uint(13));
    return res;
}
func dup15{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = dup_n(Uint(14));
    return res;
}
func dup16{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    let res = dup_n(Uint(15));
    return res;
}

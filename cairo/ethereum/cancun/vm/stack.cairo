from ethereum_types.numeric import U256, U256Struct
from ethereum_types.bytes import BytesStruct, Bytes
from starkware.cairo.common.dict import DictAccess
from ethereum.exceptions import EthereumException
from ethereum.cancun.vm.exceptions import StackOverflowError, StackUnderflowError
from legacy.utils.dict import dict_read, dict_write

struct Stack {
    value: StackStruct*,
}

struct StackStruct {
    dict_ptr_start: StackDictAccess*,
    dict_ptr: StackDictAccess*,
    len: felt,
}

struct StackDictAccess {
    key: felt,
    prev_value: U256,
    new_value: U256,
}

const STACK_MAX_SIZE = 1024;

namespace StackImpl {
    func peek{range_check_ptr, stack: Stack}(index: felt) -> felt {
        alloc_locals;
        let dict_ptr = cast(stack.value.dict_ptr, DictAccess*);
        let (value) = dict_read{dict_ptr=dict_ptr}(index);
        tempvar stack = Stack(
            new StackStruct(
                dict_ptr_start=stack.value.dict_ptr_start,
                dict_ptr=cast(dict_ptr, StackDictAccess*),
                len=stack.value.len,
            ),
        );
        return value;
    }

    func set_at{range_check_ptr, stack: Stack}(index: felt, value: felt) {
        alloc_locals;
        let dict_ptr = cast(stack.value.dict_ptr, DictAccess*);
        dict_write{dict_ptr=dict_ptr}(index, value);
        tempvar stack = Stack(
            new StackStruct(
                dict_ptr_start=stack.value.dict_ptr_start,
                dict_ptr=cast(dict_ptr, StackDictAccess*),
                len=stack.value.len,
            ),
        );
        return ();
    }
}

func pop{stack: Stack}() -> (U256, EthereumException*) {
    alloc_locals;
    let len = stack.value.len;
    if (len == 0) {
        tempvar err = new EthereumException(StackUnderflowError);
        let val = U256(cast(0, U256Struct*));
        return (val, err);
    }

    let dict_ptr = cast(stack.value.dict_ptr, DictAccess*);
    with dict_ptr {
        let (pointer) = dict_read(len - 1);
    }
    let new_dict_ptr = cast(dict_ptr, StackDictAccess*);

    tempvar stack = Stack(new StackStruct(stack.value.dict_ptr_start, new_dict_ptr, len - 1));
    tempvar value = U256(cast(pointer, U256Struct*));

    tempvar ok = cast(0, EthereumException*);
    return (value, ok);
}

func push{stack: Stack}(value: U256) -> EthereumException* {
    alloc_locals;
    let len = stack.value.len;
    if (len == STACK_MAX_SIZE) {
        tempvar err = new EthereumException(StackOverflowError);
        return err;
    }

    let dict_ptr = cast(stack.value.dict_ptr, DictAccess*);
    with dict_ptr {
        dict_write(len, cast(value.value, felt));
    }
    let new_dict_ptr = cast(dict_ptr, StackDictAccess*);

    tempvar stack = Stack(new StackStruct(stack.value.dict_ptr_start, new_dict_ptr, len + 1));
    tempvar ok = cast(0, EthereumException*);

    return ok;
}

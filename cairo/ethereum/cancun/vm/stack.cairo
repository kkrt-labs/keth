from ethereum_types.numeric import U256
from starkware.cairo.common.dict import DictAccess, dict_read, dict_write
from starkware.cairo.common.uint256 import Uint256
from ethereum.cancun.vm.exceptions import StackOverflowError, StackUnderflowError

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

func pop{stack: Stack}() -> U256 {
    alloc_locals;
    let len = stack.value.len;
    if (len == 0) {
        with_attr error_message("{error}") {
            local error = StackUnderflowError;
            assert 0 = 1;
        }
    }

    let dict_ptr = cast(stack.value.dict_ptr, DictAccess*);
    with dict_ptr {
        let (pointer) = dict_read(len - 1);
    }
    let new_dict_ptr = cast(dict_ptr, StackDictAccess*);

    tempvar stack = Stack(new StackStruct(stack.value.dict_ptr_start, new_dict_ptr, len - 1));
    tempvar value = U256(cast(pointer, Uint256*));
    return value;
}
// def push(stack: List[U256], value: U256) -> None:
//     """
//     Pushes `value` onto `stack`.

// Parameters
//     ----------
//     stack :
//         EVM stack.

// value :
//         Item to be pushed onto `stack`.

// """
//     if len(stack) == 1024:
//         raise StackOverflowError

// return stack.append(value)
// }
// }

from starkware.cairo.common.uint256 import Uint256

// Int types
struct bool {
    value: felt,
}
using Bool = bool;
struct U64 {
    value: felt,
}
struct U128 {
    value: felt,
}
struct Uint {
    value: felt,
}

using U256Struct = Uint256;
struct U256 {
    value: U256Struct*,
}

struct UnionUintU256Enum {
    uint: Uint*,
    u256: U256,
}

struct UnionUintU256 {
    value: UnionUintU256Enum*,
}

struct SetUintDictAccess {
    key: Uint,
    prev_value: bool,
    new_value: bool,
}

struct SetUintStruct {
    dict_ptr_start: SetUintDictAccess*,
    dict_ptr: SetUintDictAccess*,
}

struct SetUint {
    value: SetUintStruct*,
}

from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.cairo_builtins import UInt384

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

struct OptionalUint {
    // If `value` is the null ptr, the uint is treated as None, else, treat `value` as a felt
    // that represents the underlying uint
    value: felt*,
}

using U256Struct = Uint256;
struct U256 {
    value: U256Struct*,
}

struct OptionalU256 {
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

using U384Struct = UInt384;

struct U384 {
    value: U384Struct*,
}

struct OptionalU384 {
    value: U384Struct*,
}

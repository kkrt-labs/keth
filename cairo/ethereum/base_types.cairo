from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.uint256 import Uint256

// Int types
struct bool {
    value: felt,
}
struct U64 {
    value: felt,
}
struct U128 {
    value: felt,
}
struct Uint {
    value: felt,
}
struct U256 {
    value: Uint256*,
}

// Bytes types
struct Bytes0 {
    value: felt,
}
struct Bytes8 {
    value: felt,
}
struct Bytes20 {
    value: felt,
}
struct Bytes32 {
    value: Uint256*,
}
struct Bytes256 {
    value: U128*,
}

// Iterables types
struct BytesStruct {
    data: felt*,
    len: felt,
}

struct Bytes {
    value: BytesStruct*,
}
// Some parts of the exec spec use bytes, so just easier to copy/paste
using bytes = Bytes;

// In Cairo, tuples are not a first-class type, so we need to define a custom
// struct to represent a tuple of Bytes32.
struct TupleBytesStruct {
    value: Bytes*,
    len: felt,
}

struct TupleBytes {
    value: TupleBytesStruct*,
}

struct TupleBytes32Struct {
    value: Bytes32*,
    len: felt,
}

struct TupleBytes32 {
    value: TupleBytes32Struct*,
}

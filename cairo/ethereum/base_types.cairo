from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.uint256 import Uint256

// None values are just null pointers generally speaking (i.e. cast(my_var, felt) == 0)
// but we need to explicitly define None to be able to serialize/deserialize None
struct None {
    value: felt*,
}

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

struct StringStruct {
    data: felt*,
    len: felt,
}
struct String {
    value: StringStruct*,
}

// In Cairo, tuples are not a first-class type, so we need to define a custom
// struct to represent a tuple of Bytes32.
struct TupleBytesStruct {
    value: Bytes*,
    len: felt,
}

struct TupleBytes {
    value: TupleBytesStruct*,
}

// Just a lke regular DictAccess pointer, with keys and values to be interpreted as
// Bytes pointers.
struct BytesBytesDictAccess {
    key: Bytes,
    prev_value: Bytes,
    new_value: Bytes,
}

struct MappingBytesBytesStruct {
    dict_ptr_start: BytesBytesDictAccess*,
    dict_ptr: BytesBytesDictAccess*,
}

struct MappingBytesBytes {
    value: MappingBytesBytesStruct*,
}

struct TupleBytes32Struct {
    value: Bytes32*,
    len: felt,
}

struct TupleBytes32 {
    value: TupleBytes32Struct*,
}

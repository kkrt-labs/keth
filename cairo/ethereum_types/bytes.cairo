// The Cairo type system implementation that mirrors Python types for VM interaction.
//
// This module implements a "soft type system" that allows seamless conversion between Python
// and Cairo types. The type system follows these key principles:
//
// 1. All complex types are represented as pointers to underlying structs
// 2. Types with a single 'value' field are considered external types, pointing to a struct
// that contains the actual data.
// 3. The memory layout is consistent and predictable, allowing automatic arg generation
// 4. None values are represented as null pointers (pointer to 0)
// 5. Types maintain a consistent pattern: external type points to internal struct containing the data
//
// For example, the Bytes type follows this pattern:
// Bytes -> points to -> BytesStruct -> contains -> (data: felt*, len: felt)
//
// This design enables:
// - Consistent null pointer representation
// - Efficient memory layout (single pointer size for complex types)
// - Easy type conversion between Python and Cairo
// - Support for collections and nested types
//
// The data layout defined in this file are coherent with the Cairo arg generation process defined in args_gen.py and Cairo serialization process in serde.py

from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.math import assert_not_equal
from starkware.cairo.common.uint256 import Uint256
from src.utils.utils import Helpers
from ethereum_types.numeric import U128, bool

// Bytes types
struct Bytes0 {
    value: felt,
}
struct Bytes1 {
    value: felt,
}
struct Bytes8 {
    value: felt,
}
struct Bytes20 {
    value: felt,
}
using Bytes32Struct = Uint256;
struct Bytes32 {
    value: Bytes32Struct*,
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
    data: Bytes*,
    len: felt,
}

struct TupleBytes {
    value: TupleBytesStruct*,
}

// Important note about dictionary/mapping types:
// When the key type are pointers, accessing a dictionary with equivalent but distinct
// key objects may not work as expected. For example:
//
// If dict[b'123'] = b'345' is set, accessing with k = b'123' later may not find the value
// since k points to a different memory location than the original key, even though the
// content is identical.
//
// To prevent this, we designed the dictionary/mapping types to internally
// use the hash of the key instead of the key pointer.
// As such, `args_gen` and `serde` automatically hash keys when generating arguments for complex types.
// ([Bytes, bytes, bytearray, str, U256, Hash32, Bytes32, Bytes256]...)

// Just a like regular DictAccess pointer, with keys hashed and values to be interpreted as
// Bytes pointers.

using HashedBytes = felt;
struct BytesBytesDictAccess {
    key: HashedBytes,
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

struct TupleMappingBytesBytesStruct {
    data: MappingBytesBytes*,
    len: felt,
}

struct TupleMappingBytesBytes {
    value: TupleMappingBytesBytesStruct*,
}

struct TupleBytes32Struct {
    data: Bytes32*,
    len: felt,
}

struct TupleBytes32 {
    value: TupleBytes32Struct*,
}

struct Bytes1DictAccess {
    key: felt,
    prev_value: Bytes1,
    new_value: Bytes1,
}

func Bytes__eq__(_self: Bytes, other: Bytes) -> bool {
    if (_self.value.len != other.value.len) {
        tempvar res = bool(0);
        return res;
    }

    // Case diff: we can let the prover do the work of iterating over the bytes,
    // return the first different byte index, and assert in cairo that the a[index] != b[index]
    tempvar is_diff;
    tempvar diff_index;
    %{
        self_bytes = b''.join([memory[ids._self.value.data + i].to_bytes(1, "little") for i in range(ids._self.value.len)])
        other_bytes = b''.join([memory[ids.other.value.data + i].to_bytes(1, "little") for i in range(ids.other.value.len)])
        diff_index = next((i for i, (b_self, b_other) in enumerate(zip(self_bytes, other_bytes)) if b_self != b_other), None)
        if diff_index is not None:
            ids.is_diff = 1
            ids.diff_index = diff_index
        else:
            # No differences found in common prefix. Lengths were checked before
            ids.is_diff = 0
            ids.diff_index = 0
    %}

    if (is_diff == 1) {
        // Assert that the bytes are different at the first different index
        assert_not_equal(_self.value.data[diff_index], other.value.data[diff_index]);
        tempvar res = bool(1);
        return res;
    }

    // Case equal: we need to iterate over all keys in cairo, because the prover might not have been honest
    // about the first different byte index.
    tempvar i = 0;

    loop:
    let index = [ap - 1];
    let self_value = cast([fp - 4], BytesStruct*);
    let other_value = cast([fp - 3], BytesStruct*);

    let is_end = Helpers.is_zero(index - self_value.len);
    tempvar res = bool(1);
    jmp end if is_end != 0;

    let is_eq = Helpers.is_zero(self_value.data[index] - other_value.data[index]);

    tempvar i = i + 1;
    jmp loop if is_eq != 0;
    tempvar res = bool(0);

    end:
    let res = bool([ap - 1]);
    return res;
}

// cairo-lint: disable-file
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
from cairo_core.bytes import (
    Bytes0,
    Bytes1,
    Bytes4,
    Bytes8,
    Bytes20,
    Bytes32,
    Bytes32Struct,
    Bytes48,
    Bytes48Struct,
    Bytes256,
    BytesStruct,
    Bytes,
    bytes,
    String,
    StringStruct,
    TupleBytesStruct,
    TupleBytes,
    HashedBytes32,
    HashedBytes,
    BytesBytesDictAccess,
    MappingBytesBytes,
    MappingBytesBytesStruct,
    TupleMappingBytesBytesStruct,
    TupleMappingBytesBytes,
    TupleBytes32Struct,
    TupleBytes32,
    Bytes1DictAccess,
    ListBytes4Struct,
    ListBytes4,
    OptionalBytes,
    OptionalBytes32,
)

# Keth codebase architecture

This codebase is an EVM implementation written in Cairo Zero.

## Overview

The architecture system bridges Python and Cairo through three components:

1. Type Generation (`args_gen.py`): Converts Python values to Cairo memory
   layout according to Cairo's memory model and type system rules.

2. Serialization (`serde.py`): Interprets Cairo memory segments and reconstructs
   equivalent Python values, enabling bidirectional conversion.

3. Test Runner (`runner.py`): Orchestrates program execution, manages memory
   segments, and handles type conversions for function outputs between Python
   and Cairo.

## Type System Design

Adding new types to the Cairo type system requires implementing both the Cairo
memory representation and Python conversion logic. The Cairo implementation must
follow the established patterns for memory layout and pointer relationships,
while the Python side requires bidirectional conversion handling.

When implementing the Cairo equivalent of a python type, you should always map
the cairo type to the python type in `_cairo_struct_to_python_type` inside
`args_gen.py`.

### Error Types Pattern

Error types should:

1. Be defined in the separate `cairo/ethereum/cancun/vm/exceptions.cairo` file.
2. Follow the Bytes pattern for error messages:

```cairo
from ethereum_types.bytes import Bytes

struct StackUnderflowError {
    value: Bytes,
}

struct StackOverflowError {
    value: Bytes,
}
```

3. Return `cast(0, ErrorType*)` for success cases
4. Create a new Bytes with message for error cases. The error message can be
   empty.

```cairo
    tempvar err = StackUnderflowError(Bytes(new BytesStruct(cast(0, felt*), 0)));
```

### Implicit Arguments Pattern

When working with mutable data structures (stack, memory, state, etc.):

1. Use implicit arguments for the structure being modified
2. Return the error type if the operation can fail

Example:

````cairo
func push{stack: Stack}(value: U256) -> StackOverflowError {
    # Only return error
}

3. Return the error type as the last element of the tuple if the operation can either return a value or fail

Example:

```cairo
func pop{stack: Stack}() -> (U256, StackUnderflowError) {
    # Return both value and error
}

### Test Structure Pattern

Tests should:

1. Be organized in classes (e.g. `TestStack`)
2. Use the `cairo_run` fixture to run Cairo functions
3. Compare Python and Cairo implementations for equivalence
4. Use hypothesis for property-based testing
5. Test both success and error cases
6. Have the same path in the tests folder as the source file (e.g.
   `ethereum/crypto/hash.cairo` -> `tests/ethereum/crypto/test_hash.py`)

To run tests, use pytest with `uv`: `uv run pytest -k <test_name>`.

Example:

```python
class TestFeature:
    @given(...)
    def test_operation(self, cairo_run, ...):
        # Test success case
        result_cairo = cairo_run("operation", ...)
        result_py = operation(...)
        assert result_cairo == result_py

    @given(...)
    def test_error(self, cairo_run, ...):
        # Test error case
        with pytest.raises(ErrorType):
            cairo_run("operation", ...)
        with pytest.raises(ErrorType):
            operation(...)
````

### Type Wrapping Pattern

Complex types use pointer-based structures for consistent memory allocation. Two
main variants exist:

1. Simple wrapper (fixed-size):

```cairo
struct Bytes0 {
    value: felt,
}
```

2. Complex wrapper (variable-size):

```cairo
struct Bytes {
    value: BytesStruct*,
}

struct BytesStruct {
    data: felt*,
    len: felt,
}
```

### Optional Values Pattern

Null values implementation uses pointer semantics:

1. Simple types (direct value):

```cairo
struct U64 {
    value: felt
}
```

A `null` U64 is represented by a U64 pointer with a value of 0.

2. Complex types (pointer-based):

```cairo
struct U256 {
    value: U256Struct*,  // null when pointer is 0
}
```

A `null` U256 is represented by the inner U256Struct\* having a value of 0.

When integrating optional values in other types, we thus have two cases:

1. (simple type) We represent the option as a pointer to the value, with a value
   of 0 representing a null value.
2. (complex type) We represent the option as the type itself, as it is already a
   pointer-based type.

To make it clear to the reader, we define a type alias
`using OptionalAddress = Address*` (simple type) and
`using OptionalBytes = Bytes` (complex type).

```cairo
using OptionalAddress = Address*;
using OptionalEvm = Evm;

struct MessageStruct {
    // ... other fields ...
    code_address: OptionalAddress,
    parent_evm: OptionalEvm,
}
```

### Union Types Pattern

Unions implement a pointer-based variant system. Real example from RLP encoding,
`Union[Sequence["Simple"], bytes]` and
`Union[Sequence["Extended"], bytearray, bytes, uint, FixedUnsigned, str, bool]`:

```cairo
// Simple variant with two possibilities
struct Simple {
    value: SimpleEnum*,
}

struct SimpleEnum {
    sequence: SequenceSimple,  // First variant
    bytes: Bytes,             // Second variant
}

// Extended variant with multiple possibilities
struct Extended {
    value: ExtendedEnum*,
}

struct ExtendedEnum {
    sequence: SequenceExtended,
    bytearray: Bytes,
    bytes: Bytes,
    uint: Uint*,
    fixed_uint: Uint*,
    str: String,
    bool: Bool*,
}
```

Implementation pattern:

1. Outer struct contains pointer to enum struct
2. Enum struct contains all possible variants.
3. Only one variant is active (non-zero) at a time
4. Variant construction uses explicit constructors:

```cairo
// Example constructor for a variant
func bytes(value: Bytes) -> Extended {
    tempvar extended = Extended(
        new ExtendedEnum(
            sequence=SequenceExtended(cast(0, SequenceExtendedStruct*)),
            bytearray=Bytes(cast(0, BytesStruct*)),
            bytes=value,  // Active variant
            uint=cast(0, Uint*),
            fixed_uint=cast(0, Uint*),
            str=String(cast(0, StringStruct*)),
            bool=cast(0, Bool*),
        ),
    );
    return extended;
}
```

### Write-once Collections Pattern

The inner struct is a struct with two fields: a pointer to the collection's data
segment, and the length of the collection.

```cairo
struct Bytes {
    value: BytesStruct*,
}

struct BytesStruct {
    data: felt*,
    len: felt
}
```

We can also make collections of collections, like a tuple of bytes.

```cairo
struct TupleBytesStruct {
    data: Bytes*,  // Tuple data
    len: felt, // Number of elements in the tuple
}

struct TupleBytes {
    value: TupleBytesStruct*,
}
```

### Mappings Pattern

Implementation using DictAccess pattern from the standard library. For the
`Mapping[Bytes, Bytes]` type, the corresponding Cairo struct is:

```cairo
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
```

Key implementation notes:

- Keys are stored as pointers, thus querying a key is a pointer equality check,
  not a value equality check.
- In the future, we consider using key hashes for content-based comparison
  rather than pointer comparison.

### Mutable Collections Pattern

Cairo's write-once memory model necessitates implementing mutable collections
through a dictionary-based state tracking system. The implementation uses a
two-pointer dictionary structure to maintain state changes while preserving the
functional programming paradigm.

The base structure consists of an outer pointer wrapper and an inner struct
containing dictionary pointers and length:

```cairo
struct MutableCollection {
    value: CollectionStruct*,
}

struct CollectionStruct {
    dict_ptr_start: CollectionDictAccess*,
    dict_ptr: CollectionDictAccess*,
    len: felt,
}

struct CollectionDictAccess {
    key: KeyType,
    prev_value: ValueType,
    new_value: ValueType,
}
```

The dictionary implementation maintains state through a series of memory
segments. Each mutation operation creates a new dictionary entry rather than
modifying existing memory. The `dict_ptr_start` maintains a reference to the
initial state while `dict_ptr` advances with each mutation, creating a
modification history in the memory segment between these pointers.

For example, the Stack implementation for the EVM uses this pattern to maintain
a mutable stack of U256 values:

```cairo
struct Stack {
    value: StackStruct*,
}

struct StackStruct {
    dict_ptr_start: StackDictAccess*,
    dict_ptr: StackDictAccess*,
    len: felt,
}

struct StackDictAccess {
    key: felt,         // Stack index
    prev_value: U256,  // Previous value at index
    new_value: U256,   // New value at index
}
```

Mutation operations create new dictionary entries through the Cairo dictionary
API:

```cairo
func push{stack: Stack}(value: U256) {
    let len = stack.value.len;
    dict_write(len, cast(value.value, felt));
    tempvar stack = Stack(
        new StackStruct(
            dict_ptr_start=stack.value.dict_ptr_start,
            dict_ptr=new_dict_ptr,
            len=len + 1
        )
    );
    # `stack` is returned implicitly
}
```

### Real-World Example: TransientStorage Implementation

The TransientStorage implementation demonstrates how these patterns come
together in a real-world component. TransientStorage is a key part of the EVM,
managing temporary storage that persists between message calls within a
transaction. We will base our implementation on the `ethereum/execution-specs`
repository, in `ethereum/cancun/state.py`.

In Python, TransientStorage is a dataclass with two fields:

- `_tries`: A dictionary mapping addresses to tries
- `_snapshots`: A list of dictionaries for state history

```python
@dataclass
class TransientStorage:
    """
    Contains all information that is preserved between message calls
    within a transaction.
    """
    _tries: Dict[Address, Trie[Bytes32, U256]] = field(default_factory=dict)
    _snapshots: List[Dict[Address, Trie[Bytes32, U256]]] = field(default_factory=list)
```

Here is the Cairo implementation:

1. Type Wrapping Pattern: Following the complex wrapper pattern, we define the
   TransientStorage structure with nested pointer-based types:

```cairo:cairo/ethereum/cancun/state.cairo
struct TransientStorage {
    value: TransientStorageStruct*,
}

struct TransientStorageStruct {
    _tries: MappingAddressTrieBytes32U256,  // Dict[Address, Trie[Bytes32, U256]]
    _snapshots: TransientStorageSnapshots, // List[Dict[Address, Trie[Bytes32, U256]]]
}
```

2. Mappings Pattern: The `_tries` field uses the dictionary-based mapping
   pattern to store key-value pairs for each address:

```cairo:cairo/ethereum/cancun/state.cairo
struct AddressTrieBytes32U256DictAccess {
    key: Address,
    prev_value: TrieBytes32U256,
    new_value: TrieBytes32U256,
}

struct MappingAddressTrieBytes32U256Struct {
    dict_ptr_start: AddressTrieBytes32U256DictAccess*,
    dict_ptr: AddressTrieBytes32U256DictAccess*,
}

struct MappingAddressTrieBytes32U256 {
    value: MappingAddressTrieBytes32U256Struct*,
}
```

3. Write-once Collections Pattern: The `_snapshots` field uses the collection
   pattern to maintain a history of storage states:

```cairo:cairo/ethereum/cancun/state.cairo
struct TransientStorageSnapshotsStruct {
    data: MappingAddressTrieBytes32U256*,  // Array of mappings
    len: felt,
}

struct TransientStorageSnapshots {
    value: TransientStorageSnapshotsStruct*,
}
```

4. Python Integration:

We integrate the new external types to the Cairo <> Python type mapping:

```python:tests/utils/args_gen.py
_cairo_struct_to_python_type: Dict[Tuple[str, ...], Any] = {
    # ... existing mappings ...
    ("ethereum", "cancun", "state", "TransientStorage"): TransientStorage,
    ("ethereum", "cancun", "state", "MappingAddressTrieBytes32U256"): Mapping[
        Address, Trie[Bytes32, U256]
    ],
    ("ethereum", "cancun", "state", "TransientStorageSnapshots"): List[
        Dict[Address, Trie[Bytes32, U256]]
    ],
}
```

5. Testing Pattern: We're only adding a type without functions, so we only need
   to add the new types to `test_serde.py`.

```python:tests/test_serde.py
    def test_type(
        self,
        to_cairo_type,
        segments,
        serde,
        gen_arg,
        b: Union[
            # ... existing types ...
            TransientStorage,
            MappingAddressTrieBytes32U256,
            TransientStorageSnapshots,
        ],
    ):
        # ... existing test logic ...
```

This implementation demonstrates:

- Complex type wrapping with pointer-based structures
- Dictionary-based mappings for key-value storage
- Write-once collections for state history
- Automatic Python-Cairo type bridging
- Testing for serialization and deserialization

The TransientStorage component shows how Cairo's memory model and type system
can be used to implement complex, stateful data structures while maintaining
type safety and immutability guarantees.

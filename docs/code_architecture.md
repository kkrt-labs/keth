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

### Error Types Pattern

Error types should:

1. Be defined in the separate `cairo/ethereum/cancun/vm/exceptions.cairo` file.
2. Follow the BytesStruct pattern for error messages:

```cairo
struct ErrorType {
    value: BytesStruct*,  # Allows for error messages
}
```

3. Return `cast(0, ErrorType*)` for success cases
4. Create a new BytesStruct with message for error cases. For now the error
   message can be empty.

```cairo
    tempvar inner_error = new BytesStruct(cast(0, felt*), 0);
    let err = ErrorType(inner_error);
```

### Implicit Arguments Pattern

When implementing mutable data structures:

1. Use implicit arguments for the structure being modified
2. Return only the error type for modification operations
3. Return both the value and error for query operations

Example:

```cairo
# Modification operation
func push{stack: Stack}(value: U256) -> StackOverflowError {
    # Only return error
}

# Query operation
func pop{stack: Stack}() -> (U256, StackUnderflowError) {
    # Return both value and error
}
```

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

        # Test error case
        with pytest.raises(ErrorType):
            cairo_run("operation", ...)
```

### Custom Types

When implementing custom types:

1. Create a Python dataclass
2. Implement `gen_arg` method for Cairo memory layout
3. Add serialization logic in `serde.py`
4. Register all related types in `_cairo_struct_to_python_type`
5. Add hypothesis strategies in `strategies.py`

Example:

```python
@dataclass
class CustomList(List[T]):
    def gen_arg(self, dict_manager, segments):
        # Convert to Cairo memory layout
        pass

# Register in args_gen.py
_cairo_struct_to_python_type = {
    ("path", "to", "type"): CustomList,
    ("path", "to", "exceptions"): CustomError,
}

# Add strategy in strategies.py
custom_list = st.lists(base_strategy)
```

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
func push{stack: Stack}(value: U256) -> StackOverflowError {
    let len = stack.value.len;
    dict_write(len, cast(value.value, felt));
    tempvar stack = Stack(
        new StackStruct(
            dict_ptr_start=stack.value.dict_ptr_start,
            dict_ptr=new_dict_ptr,
            len=len + 1
        )
    );
}
```

### Real-World Example: Stack Implementation

The Stack implementation in the EVM demonstrates how these patterns come
together in a real-world component. The stack is a fundamental part of the EVM,
requiring both mutable state and error handling.

1. Error Types: First, we define the possible error conditions following the
   BytesStruct pattern. The stack can fail in two ways - underflow when popping
   from an empty stack, or overflow when pushing beyond the maximum size.

```cairo:cairo/ethereum/cancun/vm/exceptions.cairo
struct StackUnderflowError {
    value: BytesStruct*,
}

struct StackOverflowError {
    value: BytesStruct*,
}
```

2. Mutable Collection Pattern: The stack uses the dictionary-based mutable
   collection pattern. The two dictionary pointers track the history of
   modifications, while len maintains the current stack size.

```cairo:cairo/ethereum/cancun/vm/stack.cairo
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

3. Implicit Arguments and Error Handling: The stack operations follow the
   implicit arguments pattern for state modification. Push operations only
   return errors, while pop operations return both the value and potential
   error.

```cairo:cairo/ethereum/cancun/vm/stack.cairo
func push{stack: Stack}(value: U256) -> StackOverflowError {
    // Only return error type for modification
    // ...
}

func pop{stack: Stack}() -> (U256, StackUnderflowError) {
    // Return both value and error for query
    // ...
}
```

4. Python Integration: The Python side implements Stack as an extension of
   List[U256], providing custom argument generation logic to bridge between
   Python's list representation and Cairo's dictionary-based implementation.
   Because the logic on how to generate arguments is already implemented for the
   `list` type and the U256 type, we have no changes to make here.

The serialization logic reconstructs the Stack from Cairo's memory
representation back to Python. Once again, because the logic is already
implemented for the `list` type and the U256 type, we have no changes to make
here.

5. Testing Pattern: The tests use property-based testing with hypothesis to
   verify both success and error cases. Each test compares the Cairo
   implementation against an equivalent Python implementation.

```python:cairo/tests/ethereum/cancun/vm/test_stack.py
class TestStack:
    def test_pop_underflow(self, cairo_run):
        stack = []
        with pytest.raises(StackUnderflowError):
            cairo_run("pop", stack)
        with pytest.raises(StackUnderflowError):
            pop(stack)

    @given(stack=...)
    def test_pop_success(self, cairo_run, stack: List[U256]):
        assume(len(stack) > 0)

        (new_stack_cairo, popped_value_cairo) = cairo_run("pop", stack)
        popped_value_py = pop(stack)
        assert new_stack_cairo == stack
        assert popped_value_cairo == popped_value_py
```

This implementation shows how to:

- Define error types following the BytesStruct pattern
- Implement a mutable collection using the dictionary pattern
- Use implicit arguments for state modification
- Bridge between Python and Cairo types
- Structure tests with property-based testing
- Handle both success and error cases

"""
Cairo Type System - Argument Generation

This module handles the generation of Cairo memory values from Python types.
It is a core component of the type system that allows seamless conversion of Python
values into the appropriate Cairo memory layout.

Type System Patterns:

1. Type Wrapping Pattern:
   - All complex types are wrapped in a pointer-based structure
   - Example: `Bytes { value: BytesStruct* }` where BytesStruct contains actual data
   - This ensures all complex types have a consistent size of 1 pointer

2. None Value Pattern:
   - None is represented by a null pointer (pointer to 0)
   - For simple types (size 1), we use direct pointers (e.g., Uint*)
   - This optimizes memory by storing [value] instead of [ptr_value, value]
   - For complex types, we can directly use the pointer to the internal struct to check if it's None.
   - If cast(ptr, felt) == 0, then is None.

3. Union/Enum Pattern:
   - Python Unions map to Cairo "Enums"
   - Implementation: A struct with pointers for each variant
   - Only one variant has non-zero pointer
   - Example: Union[A,B,C] -> struct { a: A, b: B, c: C }
   - To check if a variant is None, we can check if the pointer is 0.

4. Collection Patterns:
   - Fixed Tuples: pointer to struct with each element
   - Variable Lists/Tuples: pointer to {data: T*, len: felt}
   - Example: List[T] -> struct { data: T*, len: felt }

5. Dictionary Pattern:
   - Maps to a DictAccess pointer structure
   - Keys and values are stored as pointers
   - Note: Key comparison is pointer-based, not value-based
   - Example: Dict[Bytes,Bytes] -> struct MappingBytesBytes { dict_ptr_start: BytesBytesDictAccess*, dict_ptr: BytesBytesDictAccess* }
    with struct BytesBytesDictAccess { key: Bytes, prev_value: Bytes, new_value: Bytes }

Implementation Notes:
- Type generation is driven by Python type, not Cairo type
- Cairo type system is consistent based on the rules defined above, allowing predictable memory layout
- Hypothesis handles test type generation (see strategies.py)
- Type associations must be explicitly declared in _cairo_struct_to_python_type

When adding new types, you must:
- Add the type to _cairo_struct_to_python_type
- Add the test generation strategy to strategies.py if it's a new type (not required when only doing composition of existing types, e.g. `Union[U256, bool]`)
"""

from collections import ChainMap, abc, defaultdict
from dataclasses import fields, is_dataclass
from functools import partial
from typing import (
    Annotated,
    Any,
    Dict,
    ForwardRef,
    List,
    Mapping,
    Optional,
    Sequence,
    Set,
    Tuple,
    Type,
    Union,
    _ProtocolMeta,
    get_args,
    get_origin,
)

from ethereum_types.bytes import Bytes, Bytes0, Bytes8, Bytes20, Bytes32, Bytes256
from ethereum_types.numeric import U64, U256, Uint
from starkware.cairo.common.dict import DictManager, DictTracker
from starkware.cairo.lang.compiler.ast.cairo_types import (
    CairoType,
    TypeFelt,
    TypePointer,
    TypeStruct,
)
from starkware.cairo.lang.compiler.identifier_definition import (
    StructDefinition,
    TypeDefinition,
)
from starkware.cairo.lang.compiler.program import Program
from starkware.cairo.lang.compiler.scoped_name import ScopedName
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.relocatable import MaybeRelocatable, RelocatableValue

from ethereum.cancun.blocks import Header, Log, Receipt, Withdrawal
from ethereum.cancun.fork_types import Account, Address, Bloom, Root, VersionedHash
from ethereum.cancun.transactions import (
    AccessListTransaction,
    BlobTransaction,
    FeeMarketTransaction,
    LegacyTransaction,
    Transaction,
)
from ethereum.cancun.trie import BranchNode, ExtensionNode, InternalNode, LeafNode, Node
from ethereum.cancun.vm.exceptions import StackOverflowError, StackUnderflowError
from ethereum.cancun.vm.gas import MessageCallGas
from ethereum.crypto.hash import Hash32
from ethereum.exceptions import EthereumException
from ethereum.rlp import Extended, Simple
from tests.utils.helpers import flatten

_cairo_struct_to_python_type: Dict[Tuple[str, ...], Any] = {
    ("ethereum_types", "others", "None"): type(None),
    ("ethereum_types", "numeric", "bool"): bool,
    ("ethereum_types", "numeric", "U64"): U64,
    ("ethereum_types", "numeric", "Uint"): Uint,
    ("ethereum_types", "numeric", "U256"): U256,
    ("ethereum_types", "numeric", "SetUint"): Set[Uint],
    ("ethereum_types", "numeric", "UnionUintU256"): Union[Uint, U256],
    ("ethereum_types", "bytes", "Bytes0"): Bytes0,
    ("ethereum_types", "bytes", "Bytes8"): Bytes8,
    ("ethereum_types", "bytes", "Bytes20"): Bytes20,
    ("ethereum_types", "bytes", "Bytes32"): Bytes32,
    ("ethereum_types", "bytes", "TupleBytes32"): Tuple[Bytes32, ...],
    ("ethereum_types", "bytes", "Bytes256"): Bytes256,
    ("ethereum_types", "bytes", "Bytes"): Bytes,
    ("ethereum_types", "bytes", "String"): str,
    ("ethereum_types", "bytes", "TupleBytes"): Tuple[Bytes, ...],
    ("ethereum_types", "bytes", "MappingBytesBytes"): Mapping[Bytes, Bytes],
    ("ethereum_types", "bytes", "TupleMappingBytesBytes"): Tuple[
        Mapping[Bytes, Bytes], ...
    ],
    ("ethereum", "cancun", "blocks", "Header"): Header,
    ("ethereum", "cancun", "blocks", "TupleHeader"): Tuple[Header, ...],
    ("ethereum", "cancun", "blocks", "Withdrawal"): Withdrawal,
    ("ethereum", "cancun", "blocks", "TupleWithdrawal"): Tuple[Withdrawal, ...],
    ("ethereum", "cancun", "blocks", "Log"): Log,
    ("ethereum", "cancun", "blocks", "TupleLog"): Tuple[Log, ...],
    ("ethereum", "cancun", "blocks", "Receipt"): Receipt,
    ("ethereum", "cancun", "fork_types", "Address"): Address,
    ("ethereum", "cancun", "fork_types", "SetAddress"): Set[Address],
    ("ethereum", "cancun", "fork_types", "Root"): Root,
    ("ethereum", "cancun", "fork_types", "Account"): Account,
    ("ethereum", "cancun", "fork_types", "Bloom"): Bloom,
    ("ethereum", "cancun", "fork_types", "VersionedHash"): VersionedHash,
    ("ethereum", "cancun", "fork_types", "TupleVersionedHash"): Tuple[
        VersionedHash, ...
    ],
    ("ethereum", "cancun", "transactions", "To"): Union[Bytes0, Address],
    ("ethereum", "cancun", "fork_types", "TupleAddressBytes32"): Tuple[
        Address, Bytes32
    ],
    ("ethereum", "cancun", "fork_types", "SetTupleAddressBytes32"): Set[
        Tuple[Address, Bytes32]
    ],
    ("ethereum", "cancun", "transactions", "LegacyTransaction"): LegacyTransaction,
    (
        "ethereum",
        "cancun",
        "transactions",
        "AccessListTransaction",
    ): AccessListTransaction,
    (
        "ethereum",
        "cancun",
        "transactions",
        "FeeMarketTransaction",
    ): FeeMarketTransaction,
    ("ethereum", "cancun", "transactions", "BlobTransaction"): BlobTransaction,
    ("ethereum", "cancun", "transactions", "Transaction"): Transaction,
    ("ethereum", "cancun", "transactions", "TupleAccessList"): Tuple[
        Tuple[Address, Tuple[Bytes32, ...]], ...
    ],
    ("ethereum", "cancun", "transactions", "AccessList"): Tuple[
        Address, Tuple[Bytes32, ...]
    ],
    ("ethereum", "cancun", "vm", "gas", "MessageCallGas"): MessageCallGas,
    ("ethereum", "rlp", "Simple"): Simple,
    ("ethereum", "rlp", "Extended"): Extended,
    ("ethereum", "rlp", "SequenceSimple"): Sequence[Simple],
    ("ethereum", "rlp", "SequenceExtended"): Sequence[Extended],
    ("ethereum", "cancun", "trie", "LeafNode"): LeafNode,
    ("ethereum", "cancun", "trie", "ExtensionNode"): ExtensionNode,
    ("ethereum", "cancun", "trie", "BranchNode"): BranchNode,
    ("ethereum", "cancun", "trie", "InternalNode"): InternalNode,
    ("ethereum", "cancun", "trie", "Node"): Node,
    ("ethereum", "cancun", "fork_types", "MappingAddressAccount"): Mapping[
        Address, Account
    ],
    ("ethereum", "exceptions", "EthereumException"): EthereumException,
    ("ethereum", "cancun", "vm", "stack", "Stack"): List[U256],
    (
        "ethereum",
        "cancun",
        "vm",
        "exceptions",
        "StackUnderflowError",
    ): StackUnderflowError,
    (
        "ethereum",
        "cancun",
        "vm",
        "exceptions",
        "StackOverflowError",
    ): StackOverflowError,
}

# In the EELS, some functions are annotated with Sequence while it's actually just Bytes.
_type_aliases = {
    Sequence: Bytes,
}


def isinstance_with_generic(obj, type_hint):
    """Check if obj is instance of a generic type."""
    if isinstance(type_hint, _ProtocolMeta):
        return False

    origin = get_origin(type_hint)
    if origin is None:
        if isinstance(obj, int):
            # int is a subclass of bool, so we need to check for bool or int
            return type(obj) is type_hint

        return isinstance(obj, type_hint)

    # Sequence should be _real_ Sequence, not bytes or str
    if origin is abc.Sequence:
        return type(obj) in (list, tuple)

    return isinstance(obj, origin)


def gen_arg(dict_manager: DictManager, segments: MemorySegmentManager):
    return partial(_gen_arg, dict_manager, segments)


def _gen_arg(
    dict_manager: DictManager,
    segments: MemorySegmentManager,
    arg_type: Type,
    arg: Any,
    annotations: Optional[Any] = None,
):
    """
    Generate a Cairo argument from a Python argument.

    This is the core function that implements the type system patterns defined in the module docstring.

    Args:
        dict_manager: Cairo dictionary manager, mapping Cairo segments to Python dicts
        segments: Cairo memory segments
        arg_type: Python type to convert from
        arg: Python value to convert

    Returns:
        Cairo memory pointer or value
    """
    if arg_type is type(None):
        return 0

    arg_type_origin = get_origin(arg_type) or arg_type
    if arg_type_origin is Annotated:
        base_type, *annotations = get_args(arg_type)
        return _gen_arg(dict_manager, segments, base_type, arg, annotations)

    if isinstance_with_generic(arg_type_origin, ForwardRef):
        arg_type = arg_type_origin._evaluate(globals(), locals(), frozenset())
        arg_type_origin = get_origin(arg_type) or arg_type

    if arg_type_origin is Union:
        # Union are represented as Enum in Cairo, with 0 pointers for all but one variant.
        struct_ptr = segments.add()
        data = [
            (
                _gen_arg(dict_manager, segments, x_type, arg)
                if isinstance_with_generic(arg, x_type)
                else 0
            )
            for x_type in get_args(arg_type)
        ]
        # Value types are not pointers by default, so we need to convert them to pointers.
        for i, (x_type, d) in enumerate(zip(get_args(arg_type), data)):
            if isinstance_with_generic(arg, x_type) and not isinstance_with_generic(
                d, RelocatableValue
            ):
                d_ptr = segments.add()
                segments.load_data(d_ptr, [d])
                data[i] = d_ptr
        segments.load_data(struct_ptr, data)
        return struct_ptr

    if arg_type_origin is list:
        # A `list` is represented as a Dict[felt, V] along with a length field.
        value_type = get_args(arg_type)[0]  # Get the concrete type parameter
        data = defaultdict(int, {k: v for k, v in enumerate(arg)})
        base = _gen_arg(dict_manager, segments, Dict[Uint, value_type], data)
        segments.load_data(base + 2, [len(arg)])
        return base

    if arg_type_origin in (tuple, Sequence, abc.Sequence):
        if arg_type_origin is tuple and (
            Ellipsis not in get_args(arg_type) or annotations
        ):
            # Case a tuple with a fixed number of elements, all of different types.
            # These are represented as a pointer to a struct with a pointer to each element.
            element_types = get_args(arg_type)

            # Handle fixed-size tuples with size annotation (e.g. Annotated[Tuple[T], N])
            if annotations and len(annotations) == 1 and len(element_types) == 1:
                element_types = element_types * annotations[0]
            elif annotations:
                raise ValueError(
                    f"Invalid tuple size annotation for {arg_type} with annotations {annotations}"
                )
            struct_ptr = segments.add()
            data = [
                _gen_arg(dict_manager, segments, element_type, value)
                for element_type, value in zip(element_types, arg)
            ]
            segments.load_data(struct_ptr, data)
            return struct_ptr

        # Case list, which is represented as a pointer to a struct with a pointer to the elements and the size.
        instances_ptr = segments.add()
        data = [_gen_arg(dict_manager, segments, get_args(arg_type)[0], x) for x in arg]
        segments.load_data(instances_ptr, data)
        struct_ptr = segments.add()
        segments.load_data(struct_ptr, [instances_ptr, len(arg)])
        return struct_ptr

    if arg_type_origin in (dict, ChainMap, abc.Mapping, set):
        dict_ptr = segments.add()
        assert dict_ptr.segment_index not in dict_manager.trackers

        if arg_type_origin is set:
            arg = {k: True for k in arg}
            arg_type = Mapping[get_args(arg_type)[0], bool]

        data = {
            _gen_arg(dict_manager, segments, get_args(arg_type)[0], k): _gen_arg(
                dict_manager, segments, get_args(arg_type)[1], v
            )
            for k, v in arg.items()
        }
        if isinstance_with_generic(arg, defaultdict):
            data = defaultdict(arg.default_factory, data)

        # This is required for tests where we read data from DictAccess segments while no dict method has been used.
        # Equivalent to doing an initial dict_read of all keys.
        initial_data = flatten([(k, v, v) for k, v in data.items()])
        segments.load_data(dict_ptr, initial_data)
        current_ptr = dict_ptr + len(initial_data)
        dict_manager.trackers[dict_ptr.segment_index] = DictTracker(
            data=data, current_ptr=current_ptr
        )
        base = segments.add()
        segments.load_data(base, [dict_ptr, current_ptr])
        return base

    if arg_type == MaybeRelocatable:
        return arg

    if is_dataclass(arg_type):
        # Dataclasses are represented as a pointer to a struct with the same fields.
        struct_ptr = segments.add()
        data = [
            _gen_arg(dict_manager, segments, f.type, getattr(arg, f.name))
            for f in fields(arg_type)
        ]
        segments.load_data(struct_ptr, data)
        return struct_ptr

    if arg_type in (U256, Hash32, Bytes32, Bytes256):
        if isinstance_with_generic(arg, U256):
            arg = arg.to_be_bytes32()[::-1]
        base = segments.add()
        segments.load_data(
            base,
            [int.from_bytes(arg[i : i + 16], "little") for i in range(0, len(arg), 16)],
        )
        return base

    if arg_type in (Bytes, bytes, bytearray, str):
        if arg is None:
            return 0
        if isinstance(arg, str):
            arg = arg.encode()
        bytes_ptr = segments.add()
        segments.load_data(bytes_ptr, list(arg))
        struct_ptr = segments.add()
        segments.load_data(struct_ptr, [bytes_ptr, len(arg)])
        return struct_ptr

    if arg_type in (int, bool, U64, Uint, Bytes0, Bytes8, Bytes20):
        return (
            int(arg)
            if not isinstance_with_generic(arg, bytes)
            else int.from_bytes(arg, "little")
        )

    if issubclass(arg_type, Exception):
        # For exceptions, we either return 0 (no error) or create an error with a message
        if arg is None:
            return 0

        error_bytes = str(arg).encode()
        message_ptr = segments.add()
        segments.load_data(message_ptr, list(error_bytes))
        struct_ptr = segments.add()
        segments.load_data(struct_ptr, [message_ptr, len(error_bytes)])
        return struct_ptr

    return arg


def to_python_type(cairo_type: Union[CairoType, Tuple[str, ...]]):
    if isinstance(cairo_type, TypeFelt):
        return int

    if isinstance(cairo_type, TypePointer):
        return RelocatableValue

    if isinstance(cairo_type, TypeStruct):
        return _cairo_struct_to_python_type.get(cairo_type.scope.path)

    if isinstance(cairo_type, Tuple):
        return _cairo_struct_to_python_type.get(cairo_type)

    raise NotImplementedError(f"Cairo type {cairo_type} not implemented")


def to_cairo_type(program: Program, type_name: Type):
    if type_name is int:
        return TypeFelt()

    if get_origin(type_name) is Annotated:
        type_name = get_args(type_name)[0]

    _python_type_to_cairo_struct = {
        v: k for k, v in _cairo_struct_to_python_type.items()
    }
    scope = ScopedName(
        _python_type_to_cairo_struct[_type_aliases.get(type_name, type_name)]
    )
    identifier = program.identifiers.as_dict()[scope]

    if isinstance(identifier, TypeDefinition):
        return identifier.cairo_type
    if isinstance(identifier, StructDefinition):
        return TypeStruct(scope=identifier.full_name, location=identifier.location)

    return identifier

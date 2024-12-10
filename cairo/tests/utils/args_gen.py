from collections import ChainMap, abc, defaultdict
from dataclasses import fields, is_dataclass
from functools import partial
from typing import (
    Any,
    Dict,
    ForwardRef,
    Mapping,
    Sequence,
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
from ethereum.cancun.vm.gas import MessageCallGas
from ethereum.crypto.hash import Hash32
from ethereum.rlp import Extended, Simple
from tests.utils.helpers import flatten

_cairo_struct_to_python_type: Dict[Tuple[str, ...], Any] = {
    ("ethereum_types", "others", "None"): type(None),
    ("ethereum_types", "numeric", "bool"): bool,
    ("ethereum_types", "numeric", "U64"): U64,
    ("ethereum_types", "numeric", "Uint"): Uint,
    ("ethereum_types", "numeric", "U256"): U256,
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
    ("ethereum", "cancun", "fork_types", "Root"): Root,
    ("ethereum", "cancun", "fork_types", "Account"): Account,
    ("ethereum", "cancun", "fork_types", "Bloom"): Bloom,
    ("ethereum", "cancun", "fork_types", "VersionedHash"): VersionedHash,
    ("ethereum", "cancun", "fork_types", "TupleVersionedHash"): Tuple[
        VersionedHash, ...
    ],
    ("ethereum", "cancun", "transactions", "To"): Union[Bytes0, Address],
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
    dict_manager: DictManager, segments: MemorySegmentManager, arg_type: Type, arg: Any
):
    """
    Generate a Cairo argument from a Python argument.
    """
    if arg_type is type(None):
        return 0

    arg_type_origin = get_origin(arg_type) or arg_type
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

    if arg_type_origin in (tuple, list, Sequence, abc.Sequence):
        if arg_type_origin is tuple and Ellipsis not in get_args(arg_type):
            # Case a tuple with a fixed number of elements, all of different types.
            # These are represented as a pointer to a struct with a pointer to each element.
            struct_ptr = segments.add()
            data = [
                _gen_arg(dict_manager, segments, x_type, x)
                for x_type, x in zip(get_args(arg_type), arg)
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

    if arg_type_origin in (dict, ChainMap, abc.Mapping):
        dict_ptr = segments.add()
        assert dict_ptr.segment_index not in dict_manager.trackers

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

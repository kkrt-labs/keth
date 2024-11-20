from collections import abc, defaultdict
from dataclasses import fields, is_dataclass
from functools import partial
from typing import Any, Dict, Sequence, Tuple, Type, Union, get_args, get_origin

from starkware.cairo.common.dict import DictManager, DictTracker
from starkware.cairo.lang.compiler.ast.cairo_types import (
    CairoType,
    TypeFelt,
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

from ethereum.base_types import (
    U64,
    U256,
    Bytes,
    Bytes0,
    Bytes8,
    Bytes20,
    Bytes32,
    Bytes256,
    Uint,
)
from ethereum.cancun.blocks import Header, Log, Receipt, Withdrawal
from ethereum.cancun.fork_types import Account, Address, Bloom, Root, VersionedHash
from ethereum.cancun.transactions import (
    AccessListTransaction,
    BlobTransaction,
    FeeMarketTransaction,
    LegacyTransaction,
    Transaction,
)
from ethereum.cancun.vm.gas import MessageCallGas
from ethereum.crypto.hash import Hash32
from ethereum.rlp import Extended, Simple

_cairo_struct_to_python_type: Dict[Tuple[str, ...], Any] = {
    ("ethereum", "base_types", "bool"): bool,
    ("ethereum", "base_types", "U64"): U64,
    ("ethereum", "base_types", "Uint"): Uint,
    ("ethereum", "base_types", "U256"): U256,
    ("ethereum", "base_types", "Bytes0"): Bytes0,
    ("ethereum", "base_types", "Bytes8"): Bytes8,
    ("ethereum", "base_types", "Bytes20"): Bytes20,
    ("ethereum", "base_types", "Bytes32"): Bytes32,
    ("ethereum", "base_types", "TupleBytes32"): Tuple[Bytes32, ...],
    ("ethereum", "base_types", "Bytes256"): Bytes256,
    ("ethereum", "base_types", "Bytes"): Bytes,
    ("ethereum", "base_types", "TupleBytes"): Tuple[Bytes, ...],
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
}


def gen_arg(dict_manager: DictManager, segments: MemorySegmentManager):
    return partial(_gen_arg, dict_manager, segments)


def _gen_arg(
    dict_manager: DictManager, segments: MemorySegmentManager, arg_type: Type, arg: Any
):
    """
    Generate a Cairo argument from a Python argument.
    """
    if get_origin(arg_type) is Union:
        # Union are represented as Enum in Cairo, with 0 pointers for all but one variant.
        struct_ptr = segments.add()
        data = [
            (
                _gen_arg(dict_manager, segments, x_type, arg)
                if isinstance(arg, x_type)
                else 0
            )
            for x_type in get_args(arg_type)
        ]
        # Value types are not pointers by default, so we need to convert them to pointers.
        for i, (x_type, d) in enumerate(zip(get_args(arg_type), data)):
            if isinstance(arg, x_type) and not isinstance(d, RelocatableValue):
                d_ptr = segments.add()
                segments.load_data(d_ptr, [d])
                data[i] = d_ptr
        segments.load_data(struct_ptr, data)
        return struct_ptr

    if get_origin(arg_type) in (tuple, list, Sequence, abc.Sequence):
        if get_origin(arg_type) is tuple and Ellipsis not in get_args(arg_type):
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

    if get_origin(arg_type) is dict:
        dict_ptr = segments.add()
        assert dict_ptr.segment_index not in dict_manager.trackers

        data = {
            k: _gen_arg(dict_manager, segments, get_args(arg_type)[1], v)
            for k, v in arg.items()
        }
        if isinstance(arg, defaultdict):
            data = defaultdict(arg.default_factory, data)

        dict_manager.trackers[dict_ptr.segment_index] = DictTracker(
            data=data, current_ptr=dict_ptr
        )
        return dict_ptr

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
        if isinstance(arg, U256):
            arg = arg.to_be_bytes32()[::-1]
        base = segments.add()
        segments.load_data(
            base,
            [int.from_bytes(arg[i : i + 16], "little") for i in range(0, len(arg), 16)],
        )
        return base

    if arg_type == Bytes:
        bytes_ptr = segments.add()
        segments.load_data(bytes_ptr, list(arg))
        struct_ptr = segments.add()
        segments.load_data(struct_ptr, [bytes_ptr, len(arg)])
        return struct_ptr

    if arg_type in (bool, U64, Uint, Bytes0, Bytes8, Bytes20):
        return int(arg) if not isinstance(arg, bytes) else int.from_bytes(arg, "little")

    return arg


def to_python_type(cairo_type: Union[CairoType, Tuple[str, ...]]):
    if isinstance(cairo_type, TypeFelt):
        return int

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
    scope = ScopedName(_python_type_to_cairo_struct[type_name])
    identifier = program.identifiers.as_dict()[scope]

    if isinstance(identifier, TypeDefinition):
        return identifier.cairo_type
    if isinstance(identifier, StructDefinition):
        return TypeStruct(scope=identifier.full_name, location=identifier.location)

    return identifier

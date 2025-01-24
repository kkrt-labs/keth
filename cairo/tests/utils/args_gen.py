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

import inspect
import sys
from collections import ChainMap, abc, defaultdict
from dataclasses import dataclass, fields, is_dataclass, make_dataclass
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
    TypeVar,
    Union,
    _ProtocolMeta,
    get_args,
    get_origin,
)

from cairo_addons.vm import DictTracker as RustDictTracker
from cairo_addons.vm import MemorySegmentManager as RustMemorySegmentManager
from cairo_addons.vm import Relocatable as RustRelocatable
from ethereum_types.bytes import (
    Bytes,
    Bytes0,
    Bytes1,
    Bytes8,
    Bytes20,
    Bytes32,
    Bytes256,
)
from ethereum_types.numeric import U64, U256, Uint
from starkware.cairo.common.dict import DictManager, DictTracker
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME
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
from starkware.cairo.lang.vm.crypto import poseidon_hash_many
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.relocatable import RelocatableValue

from ethereum.cancun.blocks import Header, Log, Receipt, Withdrawal
from ethereum.cancun.fork_types import Account, Address, Bloom, Root, VersionedHash
from ethereum.cancun.state import State, TransientStorage
from ethereum.cancun.transactions import (
    AccessListTransaction,
    BlobTransaction,
    FeeMarketTransaction,
    LegacyTransaction,
    Transaction,
)
from ethereum.cancun.trie import (
    BranchNode,
    ExtensionNode,
    InternalNode,
    LeafNode,
    Node,
    Trie,
    trie_get,
    trie_set,
)
from ethereum.cancun.vm import Environment as EnvironmentBase
from ethereum.cancun.vm import Evm as EvmBase
from ethereum.cancun.vm import Message as MessageBase
from ethereum.cancun.vm.gas import ExtendMemory, MessageCallGas
from ethereum.crypto.hash import Hash32
from ethereum.exceptions import EthereumException
from ethereum.rlp import Extended, Simple
from tests.utils.helpers import flatten

HASHED_TYPES = [
    Bytes,
    bytes,
    bytearray,
    str,
    U256,
    Hash32,
    Bytes32,
    Bytes256,
    Tuple[Bytes20, Bytes32],
    tuple[Bytes20, Bytes32],
]


class Memory(bytearray):
    pass


T = TypeVar("T")


class Stack(List[T]):
    pass


@dataclass
class FlatState:
    """A version of the State class that has flattened storage tries.
    The keys of the storage tries are of type Tuple[Address, Bytes32]
    """

    _main_trie: Trie[Address, Optional[Account]]
    _storage_tries: Trie[Tuple[Address, Bytes32], U256]
    _snapshots: List[
        Tuple[Trie[Address, Optional[Account]], Trie[Tuple[Address, Bytes32], U256]]
    ]
    created_accounts: Set[Address]

    @classmethod
    def from_state(cls, state: State) -> "FlatState":
        """Convert a State object to a FlatState object."""
        flat_state = cls(
            _main_trie=state._main_trie,
            _storage_tries=Trie(secured=True, default=U256(0), _data={}),
            _snapshots=[],
            created_accounts=state.created_accounts,
        )

        # Flatten storage tries
        for address, storage_trie in state._storage_tries.items():
            for key in storage_trie._data.keys():
                value = trie_get(storage_trie, key)
                trie_set(flat_state._storage_tries, (address, key), value)

        # Flatten snapshots
        for snapshot in state._snapshots:
            snapshot_main_trie = snapshot[0]
            snapshot_storage_tries = Trie(
                flat_state._storage_tries.secured, flat_state._storage_tries.default, {}
            )
            for address, storage_trie in snapshot[1].items():
                for key in storage_trie._data.keys():
                    value = trie_get(storage_trie, key)
                    trie_set(snapshot_storage_tries, (address, key), value)
            flat_state._snapshots.append((snapshot_main_trie, snapshot_storage_tries))

        return flat_state

    def to_state(self) -> State:
        """Convert a FlatState object back to a State object."""
        # Initialize state with main trie and created accounts
        state = State(
            _main_trie=self._main_trie,
            _storage_tries={},
            _snapshots=[],
            created_accounts=self.created_accounts,
        )

        # Unflatten storage tries by grouping by address
        for (address, key), value in self._storage_tries._data.items():
            if address not in state._storage_tries:
                state._storage_tries[address] = Trie(
                    secured=self._storage_tries.secured, default=U256(0), _data={}
                )
            trie = state._storage_tries[address]
            trie_set(trie, key, value)
            state._storage_tries[address] = trie

        # Unflatten snapshots
        for snapshot_main_trie, snapshot_storage_tries in self._snapshots:
            address_to_storage_trie = {}
            # Group storage tries by address for each snapshot
            for (address, key), value in snapshot_storage_tries._data.items():
                if address not in address_to_storage_trie:
                    address_to_storage_trie[address] = Trie(
                        secured=snapshot_storage_tries.secured,
                        default=U256(0),
                        _data={},
                    )
                trie = address_to_storage_trie[address]
                trie_set(trie, key, value)
                address_to_storage_trie[address] = trie
            state._snapshots.append((snapshot_main_trie, address_to_storage_trie))

        return state


@dataclass
class FlatTransientStorage:
    """A version of the TransientStorage class that has flattened storage tries.
    The keys of the storage tries are of type Tuple[Address, Bytes32]
    """

    _tries: Trie[Tuple[Address, Bytes32], U256]
    _snapshots: List[Trie[Tuple[Address, Bytes32], U256]]

    @classmethod
    def from_transient_storage(cls, ts: TransientStorage) -> "FlatTransientStorage":
        """Convert a TransientStorage object to a FlatTransientStorage object."""
        flat_ts = cls(
            _tries=Trie(secured=True, default=U256(0), _data={}),
            _snapshots=[],
        )

        # Flatten tries
        for address, storage_trie in ts._tries.items():
            for key in storage_trie._data.keys():
                value = trie_get(storage_trie, key)
                trie_set(flat_ts._tries, (address, key), value)

        # Flatten snapshots
        for snapshot in ts._snapshots:
            snapshot_tries = Trie(flat_ts._tries.secured, flat_ts._tries.default, {})
            for address, storage_trie in snapshot.items():
                for key in storage_trie._data.keys():
                    value = trie_get(storage_trie, key)
                    trie_set(snapshot_tries, (address, key), value)
            flat_ts._snapshots.append(snapshot_tries)

        return flat_ts

    def to_transient_storage(self) -> TransientStorage:
        """Convert a FlatTransientStorage object back to a TransientStorage object."""
        # Initialize transient storage
        ts = TransientStorage()

        # Unflatten tries by grouping by address
        for (address, key), value in self._tries._data.items():
            if address not in ts._tries:
                ts._tries[address] = Trie(
                    secured=self._tries.secured, default=U256(0), _data={}
                )
            trie = ts._tries[address]
            trie_set(trie, key, value)
            ts._tries[address] = trie

        # Unflatten snapshots
        for snapshot_tries in self._snapshots:
            address_to_storage_trie = {}
            # Group storage tries by address for each snapshot
            for (address, key), value in snapshot_tries._data.items():
                if address not in address_to_storage_trie:
                    address_to_storage_trie[address] = Trie(
                        secured=snapshot_tries.secured,
                        default=U256(0),
                        _data={},
                    )
                trie = address_to_storage_trie[address]
                trie_set(trie, key, value)
                address_to_storage_trie[address] = trie
            ts._snapshots.append(address_to_storage_trie)

        return ts


@dataclass
class Environment(
    make_dataclass(
        "Environment",
        [(f.name, f.type, f) for f in fields(EnvironmentBase) if f.name != "traces"],
        namespace={"__doc__": EnvironmentBase.__doc__},
    )
):
    """A version of Environment that excludes the traces field, which is not used during execution."""

    pass


@dataclass
class Message(
    make_dataclass(
        "Message",
        [
            (f.name, f.type if f.name != "parent_evm" else Optional["Evm"], f)
            for f in fields(MessageBase)
        ],
        namespace={"__doc__": MessageBase.__doc__},
    )
):
    pass


_field_mapping = {
    "stack": Stack[U256],
    "memory": Memory,
    "env": Environment,
    "error": Optional[EthereumException],
    "message": Message,
}


@dataclass
class Evm(
    make_dataclass(
        "Evm",
        [(f.name, _field_mapping.get(f.name, f.type), f) for f in fields(EvmBase)],
        namespace={"__doc__": EvmBase.__doc__},
    )
):
    def __eq__(self, other):
        return all(
            getattr(self, field.name) == getattr(other, field.name)
            for field in fields(self)
            if field.name != "error"
        ) and type(self.error) is type(other.error)


vm_exception_classes = inspect.getmembers(
    sys.modules["ethereum.cancun.vm.exceptions"],
    lambda x: inspect.isclass(x) and issubclass(x, EthereumException),
)

vm_exception_mappings = {
    (
        "ethereum",
        "cancun",
        "vm",
        "exceptions",
        f"{name}",
    ): cls
    for name, cls in vm_exception_classes
}

_cairo_struct_to_python_type: Dict[Tuple[str, ...], Any] = {
    ("ethereum_types", "others", "None"): type(None),
    ("ethereum_types", "numeric", "bool"): bool,
    ("ethereum_types", "numeric", "U64"): U64,
    ("ethereum_types", "numeric", "Uint"): Uint,
    ("ethereum_types", "numeric", "U256"): U256,
    ("ethereum_types", "numeric", "SetUint"): Set[Uint],
    ("ethereum_types", "numeric", "UnionUintU256"): Union[Uint, U256],
    ("ethereum_types", "bytes", "Bytes0"): Bytes0,
    ("ethereum_types", "bytes", "Bytes1"): Bytes1,
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
    ("ethereum", "cancun", "fork_types", "OptionalAccount"): Optional[Account],
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
    ("ethereum_types", "others", "TupleU256U256"): Tuple[U256, U256],
    ("ethereum_types", "others", "ListTupleU256U256"): List[Tuple[U256, U256]],
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
    ("ethereum", "cancun", "trie", "TrieAddressOptionalAccount"): Trie[
        Address, Optional[Account]
    ],
    ("ethereum", "cancun", "trie", "TrieTupleAddressBytes32U256"): Trie[
        Tuple[Address, Bytes32], U256
    ],
    ("ethereum", "cancun", "fork_types", "MappingAddressAccount"): Mapping[
        Address, Account
    ],
    ("ethereum", "cancun", "fork_types", "MappingTupleAddressBytes32U256"): Mapping[
        Tuple[Address, Bytes32], U256
    ],
    ("ethereum", "exceptions", "EthereumException"): EthereumException,
    ("ethereum", "cancun", "vm", "memory", "Memory"): Memory,
    ("ethereum", "cancun", "vm", "stack", "Stack"): Stack[U256],
    ("ethereum", "cancun", "trie", "Subnodes"): Annotated[Tuple[Extended, ...], 16],
    ("ethereum", "cancun", "state", "TransientStorage"): TransientStorage,
    ("ethereum", "cancun", "fork_types", "ListTupleAddressBytes32"): List[
        Tuple[Address, Bytes32]
    ],
    ("ethereum", "cancun", "state", "ListTrieTupleAddressBytes32U256"): List[
        Trie[Tuple[Address, Bytes32], U256]
    ],
    (
        "ethereum",
        "cancun",
        "state",
        "ListTupleTrieAddressOptionalAccountTrieTupleAddressBytes32U256",
    ): List[
        Tuple[Trie[Address, Optional[Account]], Trie[Tuple[Address, Bytes32], U256]]
    ],
    (
        "ethereum",
        "cancun",
        "state",
        "TupleTrieAddressOptionalAccountTrieTupleAddressBytes32U256",
    ): Tuple[Trie[Address, Optional[Account]], Trie[Tuple[Address, Bytes32], U256]],
    ("ethereum", "cancun", "state", "State"): State,
    ("ethereum", "cancun", "vm", "Environment"): Environment,
    ("ethereum", "cancun", "fork_types", "ListHash32"): List[Hash32],
    ("ethereum", "cancun", "vm", "Message"): Message,
    ("ethereum", "cancun", "vm", "Evm"): Evm,
    ("ethereum", "cancun", "vm", "Memory"): Memory,
    ("ethereum", "cancun", "vm", "Stack"): Stack[U256],
    ("ethereum", "cancun", "vm", "gas", "ExtendMemory"): ExtendMemory,
    **vm_exception_mappings,
    # For tests only
    ("tests", "src", "utils", "test_dict", "MappingUintUint"): Mapping[Uint, Uint],
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


def gen_arg(dict_manager, segments):
    return partial(_gen_arg, dict_manager, segments)


def _gen_arg(
    dict_manager,
    segments: Union[MemorySegmentManager, RustMemorySegmentManager],
    arg_type: Type,
    arg: Any,
    annotations: Optional[Any] = None,
    hash_mode: Optional[bool] = None,
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

    # arg_type = Optional[T] <=> arg_type_origin = Union[T, None]
    if arg_type_origin is Union and get_args(arg_type)[1] is type(None):
        if arg is None:
            return 0
        value = _gen_arg(dict_manager, segments, get_args(arg_type)[0], arg)
        if isinstance(value, RustRelocatable) or isinstance(value, RelocatableValue):
            # struct SomeClassStruct1 {
            #     maybe_bytes: BytesStruct*
            # }
            # if arg is not None, value is already a pointer != 0

            return value
        # struct SomeClassStruct {
        #     maybe_address: Address*
        # }
        # if arg is not none, value = Bytes20 = 0x123, which must be wrapped in a pointer.

        ptr = segments.add()
        segments.load_data(ptr, [value])
        return ptr

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
            if (
                isinstance_with_generic(arg, x_type)
                and not isinstance_with_generic(d, RustRelocatable)
                and not isinstance_with_generic(d, RelocatableValue)
            ):
                d_ptr = segments.add()
                segments.load_data(d_ptr, [d])
                data[i] = d_ptr
        segments.load_data(struct_ptr, data)
        return struct_ptr

    if arg_type_origin in (Stack, Memory):
        # Collection types are represented as a Dict[felt, V] along with a length field.
        # Get the concrete type parameter. For bytearray, the value type is int.
        value_type = next(iter(get_args(arg_type)), int)
        data = defaultdict(int, {k: v for k, v in enumerate(arg)})
        # Use regular, non-hashed dict entries for stack and memory.
        base = _gen_arg(
            dict_manager, segments, Dict[Uint, value_type], data, hash_mode=False
        )
        segments.load_data(base + 2, [len(arg)])
        return base

    if arg_type_origin in (tuple, list, Sequence, abc.Sequence):
        if arg_type_origin is tuple and (
            Ellipsis not in get_args(arg_type) or annotations
        ):
            # Case a tuple with a fixed number of elements, all of different types.
            # These are represented as a pointer to a struct with a pointer to each element.
            element_types = get_args(arg_type)

            # Handle fixed-size tuples with size annotation (e.g. Annotated[Tuple[T, ...], N])
            if (
                annotations
                and len(annotations) == 1
                and len(element_types) == 2
                and element_types[1] == Ellipsis
            ):
                element_types = [element_types[0]] * annotations[0]
            elif annotations:
                raise ValueError(
                    f"Invalid tuple size annotation for {arg_type} with annotations {annotations}"
                )
            struct_ptr = segments.add()
            data = [
                _gen_arg(
                    dict_manager, segments, element_type, value, hash_mode=hash_mode
                )
                for element_type, value in zip(element_types, arg)
            ]
            if hash_mode:
                return tuple(flatten(data))
            segments.load_data(struct_ptr, data)
            return struct_ptr

        # Case list, which is represented as a pointer to a struct with a pointer to the elements and the size.
        instances_ptr = segments.add()
        data = [
            _gen_arg(
                dict_manager, segments, get_args(arg_type)[0], x, hash_mode=hash_mode
            )
            for x in arg
        ]
        if hash_mode:
            return tuple(flatten(data))
        segments.load_data(instances_ptr, data)
        struct_ptr = segments.add()
        segments.load_data(struct_ptr, [instances_ptr, len(arg)])
        return struct_ptr

    if arg_type_origin in (dict, ChainMap, abc.Mapping, set):
        return generate_dict_arg(
            dict_manager, segments, arg_type, arg_type_origin, arg, hash_mode=hash_mode
        )

    if arg_type in (Union[int, RustRelocatable], Union[int, RelocatableValue]):
        return arg

    if is_dataclass(arg_type_origin):
        # Get the concrete type arguments if this is a generic dataclass
        type_args = get_args(arg_type)

        type_bindings = {}
        if type_args:
            type_params = arg_type_origin.__parameters__
            type_bindings = dict(zip(type_params, type_args))

        if arg_type_origin is State:
            return generate_state_arg(dict_manager, segments, arg)

        if arg_type_origin is TransientStorage:
            return generate_transient_storage_arg(dict_manager, segments, arg)

        # Dataclasses are represented as a pointer to a struct with the same fields.
        struct_ptr = segments.add()
        data = [
            _gen_arg(
                dict_manager,
                segments,
                _bind_generics(f.type, type_bindings),
                getattr(arg, f.name),
            )
            for f in fields(arg_type_origin)
        ]

        segments.load_data(struct_ptr, data)

        if arg_type_origin is Trie:
            # In case of a Trie, we need the dict to be a defaultdict with the trie.default as the default value.
            dict_ptr = segments.memory.get(data[2])
            current_ptr = segments.memory.get(data[2] + 1)
            if isinstance(dict_manager, DictManager):
                dict_manager.trackers[dict_ptr.segment_index].data = defaultdict(
                    lambda: data[1], dict_manager.trackers[dict_ptr.segment_index].data
                )
            else:
                dict_manager.trackers[dict_ptr.segment_index] = RustDictTracker(
                    data=dict_manager.trackers[dict_ptr.segment_index].data,
                    current_ptr=current_ptr,
                    default_value=data[1],
                )
        return struct_ptr

    if arg_type in (U256, Hash32, Bytes32, Bytes256):
        if isinstance_with_generic(arg, U256):
            arg = arg.to_be_bytes32()[::-1]

        felt_values = [
            int.from_bytes(arg[i : i + 16], "little") for i in range(0, len(arg), 16)
        ]

        if hash_mode:
            return tuple(felt_values)

        base = segments.add()
        segments.load_data(base, felt_values)
        return base

    if arg_type in (Bytes, bytes, bytearray, str):
        if arg is None:
            return 0
        if isinstance(arg, str):
            arg = arg.encode()

        if hash_mode:
            return tuple(list(arg))

        bytes_ptr = segments.add()
        segments.load_data(bytes_ptr, list(arg))
        struct_ptr = segments.add()
        segments.load_data(struct_ptr, [bytes_ptr, len(arg)])
        return struct_ptr

    if arg_type in (int, bool, U64, Uint, Bytes0, Bytes8, Bytes20):
        if arg_type is int and arg < 0:
            ret_value = arg + DEFAULT_PRIME
            return tuple([ret_value]) if hash_mode else ret_value

        ret_value = (
            int(arg)
            if not isinstance_with_generic(arg, bytes)
            else int.from_bytes(arg, "little")
        )

        return tuple([ret_value]) if hash_mode else ret_value

    if isinstance(arg_type, type) and issubclass(arg_type, Exception):
        # For exceptions, we either return 0 (no error) or the ascii representation of the error message
        if arg is None:
            return 0
        error_bytes = str(arg.__class__.__name__).encode()
        error_int = int.from_bytes(error_bytes, "big")
        return error_int

    return arg


def generate_trie_arg(
    dict_manager,
    segments: Union[MemorySegmentManager, RustMemorySegmentManager],
    arg_type: Trie,
    arg: Trie,
    parent_trie_data: Optional[RelocatableValue] = None,
):
    secured = _gen_arg(dict_manager, segments, type(arg.secured), arg.secured)
    default = _gen_arg(dict_manager, segments, type(arg.default), arg.default)
    data = generate_dict_arg(
        dict_manager,
        segments,
        arg_type,
        arg_type,
        arg._data,
        parent_ptr=parent_trie_data,
    )
    base = segments.add()
    segments.load_data(base, [secured, default, data])

    # In case of a Trie, we need the dict to be a defaultdict with the trie.default as the default value.
    dict_ptr = segments.memory.get(data)
    current_ptr = segments.memory.get(data + 1)

    if isinstance(dict_manager, DictManager):
        dict_manager.trackers[dict_ptr.segment_index].data = defaultdict(
            lambda: default, dict_manager.trackers[dict_ptr.segment_index].data
        )
    else:
        dict_manager.trackers[dict_ptr.segment_index] = RustDictTracker(
            data=dict_manager.trackers[dict_ptr.segment_index].data,
            current_ptr=current_ptr,
            default_value=default,
        )

    return base


def generate_state_arg(
    dict_manager,
    segments: Union[MemorySegmentManager, RustMemorySegmentManager],
    arg: State,
):
    flat_state = FlatState.from_state(arg)

    parent_main_trie_data = 0
    parent_storage_tries_data = 0
    snapshots0_storage_tries_ptr = 0

    for i, snap in enumerate(flat_state._snapshots):
        main_trie, storage_tries = snap
        snap_trie = generate_trie_arg(
            dict_manager,
            segments,
            Trie[Address, Optional[Account]],
            main_trie,
            parent_trie_data=parent_main_trie_data,
        )
        snap_storage_tries = generate_trie_arg(
            dict_manager,
            segments,
            Trie[Tuple[Address, Bytes32], U256],
            storage_tries,
            parent_trie_data=parent_storage_tries_data,
        )
        parent_main_trie_data = segments.memory.get(snap_trie + 2)
        parent_storage_tries_data = segments.memory.get(snap_storage_tries + 2)
        # Save the pointer to the first storage tries, which is our original_storage_tries field in the Cairo State.
        if i == 0:
            snapshots0_storage_tries_ptr = snap_storage_tries

    main_trie = generate_trie_arg(
        dict_manager,
        segments,
        Trie[Address, Optional[Account]],
        flat_state._main_trie,
        parent_trie_data=parent_main_trie_data,
    )
    storage_tries = generate_trie_arg(
        dict_manager,
        segments,
        Trie[Tuple[Address, Bytes32], U256],
        flat_state._storage_tries,
        parent_trie_data=parent_storage_tries_data,
    )
    created_accounts = _gen_arg(
        dict_manager, segments, Set[Address], flat_state.created_accounts
    )

    base = segments.add()
    segments.load_data(
        base,
        [
            main_trie,
            storage_tries,
            created_accounts,
            snapshots0_storage_tries_ptr,
        ],
    )
    return base


def generate_transient_storage_arg(
    dict_manager,
    segments: Union[MemorySegmentManager, RustMemorySegmentManager],
    arg: TransientStorage,
):
    flat_transient_storage = FlatTransientStorage.from_transient_storage(arg)
    parent_trie_data = 0

    # Process snapshots first to generate the recursive trie structure.
    for snap in flat_transient_storage._snapshots:
        snap_trie = generate_trie_arg(
            dict_manager,
            segments,
            Trie[Tuple[Address, Bytes32], U256],
            snap,
            parent_trie_data=parent_trie_data,
        )
        parent_trie_data = segments.memory.get(snap_trie + 2)

    # Generate the main transient storage trie
    main_transient_storage_trie = generate_trie_arg(
        dict_manager,
        segments,
        Trie[Tuple[Address, Bytes32], U256],
        flat_transient_storage._tries,
        parent_trie_data=parent_trie_data,
    )

    base = segments.add()
    segments.load_data(base, [main_transient_storage_trie])
    return base


def generate_dict_arg(
    dict_manager,
    segments: Union[MemorySegmentManager, RustMemorySegmentManager],
    arg_type: Type,
    arg_type_origin: Type,
    arg: Any,
    hash_mode: Optional[bool] = None,
    parent_ptr: Optional[RelocatableValue] = None,
):

    dict_ptr = segments.add()

    if arg_type_origin is set:
        arg = defaultdict(lambda: False, {k: True for k in arg})
        arg_type = Mapping[get_args(arg_type)[0], bool]

    data = {
        _gen_arg(
            dict_manager,
            segments,
            get_args(arg_type)[0],
            k,
            hash_mode=hash_mode in (True, None),
        ): _gen_arg(dict_manager, segments, get_args(arg_type)[1], v)
        for k, v in arg.items()
    }

    if isinstance_with_generic(arg, defaultdict):
        data = defaultdict(arg.default_factory, data)

    # This is required for tests where we read data from DictAccess segments while no dict method has been used.
    # Equivalent to doing an initial dict_read of all keys.
    # We only hash keys if they're in tuples.

    # In case of a dict update, we need to get the prev_value from the dict_tracker of the parent_ptr.
    # For consistency purposes when we drop the dict and put its prev values back in the parent_ptr.
    parent_dict_end_ptr = segments.memory.get(parent_ptr + 1) if parent_ptr else None
    initial_data = flatten(
        [
            (
                (poseidon_hash_many(k) if get_args(arg_type)[0] in HASHED_TYPES else k),
                (
                    dict_manager.get_tracker(parent_dict_end_ptr).data.get(k, v)
                    if parent_dict_end_ptr
                    else v
                ),
                v,
            )
            for k, v in data.items()
        ]
    )

    segments.load_data(dict_ptr, initial_data)
    current_ptr = dict_ptr + len(initial_data)

    if isinstance(dict_manager, DictManager):
        dict_manager.trackers[dict_ptr.segment_index] = DictTracker(
            data=data, current_ptr=current_ptr
        )
    else:
        default_value = (
            data.default_factory() if isinstance(data, defaultdict) else None
        )
        dict_manager.trackers[dict_ptr.segment_index] = RustDictTracker(
            data=data,
            current_ptr=current_ptr,
            default_value=default_value,
        )

    base = segments.add()

    # The last element is the original_segment_stop pointer.
    # Because this is a new dict, this is 0 (null ptr).
    # This does not apply to stack and memory (hash_mode=False), in which case there's only 2 elements.
    data_to_load = (
        [dict_ptr, current_ptr, parent_ptr or 0]
        if (hash_mode is not False)
        else [dict_ptr, current_ptr]
    )
    segments.load_data(base, data_to_load)
    return base


def _bind_generics(type_hint, bindings):
    """Recursively bind generic type parameters."""
    # If the type is directly in bindings, return the bound type
    if type_hint in bindings:
        return bindings[type_hint]

    # Get the origin type (e.g., Dict from Dict[K, V])
    origin = get_origin(type_hint)
    if origin is None:
        return type_hint

    # Get and bind the type arguments
    args = get_args(type_hint)
    bound_args = tuple(_bind_generics(arg, bindings) for arg in args)

    # Reconstruct the type with bound arguments
    return origin[bound_args]


def to_python_type(cairo_type: Union[CairoType, Tuple[str, ...], str]):
    if isinstance(cairo_type, TypeFelt):
        return int

    if isinstance(cairo_type, TypePointer):
        return RustRelocatable

    if isinstance(cairo_type, TypeStruct):
        # Some mappings have keys that are hashed. In that case, the cairo type name starts with "Hashed".
        # We need to remove the "Hashed" prefix to get the original type name.
        unhashed_path = cairo_type.scope.path[:-1] + (
            cairo_type.scope.path[-1].removeprefix("Hashed"),
        )
        return _cairo_struct_to_python_type.get(unhashed_path)

    if isinstance(cairo_type, Tuple):
        return _cairo_struct_to_python_type.get(cairo_type)

    if isinstance(cairo_type, str):
        for k, v in _cairo_struct_to_python_type.items():
            if k[-1] == cairo_type:
                return v

    raise NotImplementedError(f"Cairo type {cairo_type} not implemented")


def to_cairo_type(program: Program, type_name: Type):
    if type_name is int:
        return TypeFelt()

    if get_origin(type_name) is Annotated:
        type_name = get_args(type_name)[0]

    _python_type_to_cairo_struct = {
        v: k for k, v in _cairo_struct_to_python_type.items()
    }

    if isinstance(type_name, type) and issubclass(type_name, Exception):
        scope = ScopedName(_python_type_to_cairo_struct[EthereumException])
    else:
        scope = ScopedName(
            _python_type_to_cairo_struct[_type_aliases.get(type_name, type_name)]
        )

    identifier = program.identifiers.as_dict()[scope]

    if isinstance(identifier, TypeDefinition):
        return identifier.cairo_type
    if isinstance(identifier, StructDefinition):
        return TypeStruct(scope=identifier.full_name, location=identifier.location)

    return identifier

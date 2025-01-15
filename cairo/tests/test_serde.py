from typing import Annotated, Any, List, Mapping, Optional, Set, Tuple, Type, Union

import pytest
from ethereum_types.bytes import Bytes, Bytes0, Bytes8, Bytes20, Bytes32, Bytes256
from ethereum_types.numeric import U64, U256, Uint
from hypothesis import HealthCheck, assume, given, settings
from starkware.cairo.common.dict import DictManager
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME
from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager

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
)
from ethereum.cancun.vm.exceptions import (
    InvalidOpcode,
    StackOverflowError,
    StackUnderflowError,
)
from ethereum.cancun.vm.gas import ExtendMemory, MessageCallGas
from ethereum.crypto.hash import Hash32
from ethereum.exceptions import EthereumException
from tests.utils.args_gen import (
    Environment,
    Evm,
    Memory,
    Message,
    Stack,
    _cairo_struct_to_python_type,
)
from tests.utils.args_gen import gen_arg as _gen_arg
from tests.utils.args_gen import to_cairo_type as _to_cairo_type
from tests.utils.serde import Serde
from tests.utils.strategies import TypedTuple


@pytest.fixture(scope="module")
def segments():
    return MemorySegmentManager(memory=MemoryDict(), prime=DEFAULT_PRIME)


@pytest.fixture(scope="module")
def dict_manager():
    return DictManager()


@pytest.fixture(scope="module")
def serde(cairo_program, segments, dict_manager):
    return Serde(segments, cairo_program, dict_manager)


@pytest.fixture(scope="module")
def gen_arg(dict_manager, segments):
    return _gen_arg(dict_manager, segments)


@pytest.fixture(scope="module")
def to_cairo_type(cairo_program):
    def _factory(type_name: Type):
        return _to_cairo_type(cairo_program, type_name)

    return _factory


def get_type(instance: Any) -> Type:
    if isinstance(instance, Mapping):
        # Get key and value types from the first item in the mapping
        if instance:
            key_type = get_type(next(iter(instance.keys())))
            value_type = get_type(next(iter(instance.values())))
            return Mapping[key_type, value_type]
        return Mapping

    if isinstance(instance, Set):
        if instance:
            item_type = get_type(next(iter(instance)))
            return Set[item_type]
        return Set

    if isinstance(instance, Trie):
        key_type, value_type = instance.__orig_class__.__args__
        return Trie[key_type, value_type]

    if isinstance(instance, TypedTuple):
        args = instance.__orig_class__.__args__
        return Tuple[args]

    if not isinstance(instance, (tuple, list)):
        return type(instance)

    # Empty sequence
    if not instance:
        return tuple if isinstance(instance, tuple) else list

    # Get all element types
    elem_types = [get_type(x) for x in instance]

    type_mapping = {
        tuple: lambda types: (
            Tuple[types[0], ...]
            if all(t == types[0] for t in types)
            else Tuple[tuple(types)]
        ),
        Stack: lambda types: (
            Stack[types[0]] if all(t == types[0] for t in types) else Stack[types]
        ),
        list: lambda types: (
            List[types[0]] if all(t == types[0] for t in types) else List[types]
        ),
    }

    # Get the appropriate constructor based on instance type, defaulting to List
    type_constructor = type_mapping.get(type(instance))
    return type_constructor(elem_types)


def is_sequence(value: Any) -> bool:
    return (
        isinstance(value, tuple)
        or isinstance(value, list)
        or isinstance(value, Mapping)
        or isinstance(value, Set)
    )


def no_empty_sequence(value: Any) -> bool:
    """Recursively check that no tuples (including nested ones) are empty."""
    if not is_sequence(value):
        return True

    if isinstance(value, Mapping) or isinstance(value, Set):
        return len(value) > 0

    if not value:  # Empty tuple
        return False

    # Check each element recursively if it's a tuple
    return all(no_empty_sequence(x) if is_sequence(x) else True for x in value)


def single_evm_parent(b: Union[Message, Evm]) -> bool:
    if isinstance(b, Message):
        if b.parent_evm is not None:
            return b.parent_evm.message.parent_evm is None

    if isinstance(b, Evm):
        message = b.message
        if message.parent_evm is not None:
            return message.parent_evm.message.parent_evm is None

    return True


class TestSerde:
    @given(b=...)
    # 20 examples per type
    # Cannot build a type object from the dict until we upgrade to python 3.12
    @settings(
        max_examples=20 * len(_cairo_struct_to_python_type),
        suppress_health_check=[HealthCheck.data_too_large, HealthCheck.filter_too_much],
    )
    def test_type(
        self,
        to_cairo_type,
        segments,
        serde,
        gen_arg,
        b: Union[
            bool,
            U64,
            Uint,
            U256,
            Bytes0,
            Bytes8,
            Bytes20,
            Bytes32,
            Tuple[Bytes32, ...],
            Bytes256,
            Bytes,
            Tuple[Bytes, ...],
            Header,
            Tuple[Header, ...],
            Withdrawal,
            Tuple[Withdrawal, ...],
            Log,
            Tuple[Log, ...],
            Receipt,
            Address,
            Root,
            Account,
            Bloom,
            VersionedHash,
            Tuple[VersionedHash, ...],
            Union[Bytes0, Address],
            LegacyTransaction,
            AccessListTransaction,
            FeeMarketTransaction,
            BlobTransaction,
            Transaction,
            Tuple[Tuple[Address, Tuple[Bytes32, ...]], ...],
            Tuple[Address, Tuple[Bytes32, ...]],
            MessageCallGas,
            LeafNode,
            ExtensionNode,
            BranchNode,
            InternalNode,
            Optional[InternalNode],
            Node,
            Mapping[Bytes, Bytes],
            Tuple[Mapping[Bytes, Bytes], ...],
            Set[Uint],
            Mapping[Address, Account],
            Tuple[Address, Bytes32],
            Set[Tuple[Address, Bytes32]],
            Union[Uint, U256],
            Set[Address],
            Annotated[Tuple[VersionedHash, ...], 16],
            Mapping[Bytes32, U256],
            Trie[Bytes32, U256],
            Trie[Address, Optional[Account]],
            TransientStorage,
            Mapping[Address, Trie[Bytes32, U256]],
            State,
            Tuple[
                Trie[Address, Optional[Account]], Mapping[Address, Trie[Bytes32, U256]]
            ],
            List[
                Tuple[
                    Trie[Address, Optional[Account]],
                    Mapping[Address, Trie[Bytes32, U256]],
                ]
            ],
            List[Hash32],
            Environment,
            Stack[U256],
            Memory,
            Evm,
            Message,
            List[Tuple[U256, U256]],
            ExtendMemory,
        ],
    ):
        assume(no_empty_sequence(b))
        assume(single_evm_parent(b))
        type_ = get_type(b)
        base = segments.gen_arg([gen_arg(type_, b)])
        result = serde.serialize(to_cairo_type(type_), base, shift=0)
        assert result == b

    @given(err=...)
    def test_exception(
        self,
        to_cairo_type,
        segments,
        serde,
        gen_arg,
        err: Union[
            EthereumException, StackOverflowError, StackUnderflowError, InvalidOpcode
        ],
    ):
        base = segments.gen_arg([gen_arg(type(err), err)])
        result = serde.serialize(to_cairo_type(type(err)), base, shift=0)
        assert issubclass(result.__class__, Exception)

    @pytest.mark.parametrize(
        "error_type",
        [EthereumException, StackOverflowError, StackUnderflowError, InvalidOpcode],
    )
    def test_none_exception(self, to_cairo_type, serde, gen_arg, error_type):
        base = gen_arg(error_type, None)
        result = serde.serialize(to_cairo_type(error_type), base, shift=0)
        assert result is None

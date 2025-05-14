from collections import ChainMap
from typing import Annotated, Any, List, Mapping, Optional, Set, Tuple, Type, Union

import pytest
from ethereum.cancun.blocks import Block, Header, Log, Receipt, Withdrawal
from ethereum.cancun.fork import BlockChain
from ethereum.cancun.fork_types import Account, Address, Bloom, Root, VersionedHash
from ethereum.cancun.state import State, TransientStorage
from ethereum.cancun.transactions import (
    Access,
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
from ethereum.cancun.vm import (
    BlockEnvironment,
    BlockOutput,
    Evm,
    Message,
    TransactionEnvironment,
)
from ethereum.cancun.vm.exceptions import (
    InvalidOpcode,
    Revert,
    StackOverflowError,
    StackUnderflowError,
)
from ethereum.cancun.vm.gas import ExtendMemory, MessageCallGas
from ethereum.cancun.vm.interpreter import MessageCallOutput
from ethereum.crypto.alt_bn128 import BNF, BNF2, BNF12, BNP, BNP2
from ethereum.crypto.hash import Hash32
from ethereum.crypto.kzg import FQ, FQ2, BLSFieldElement, KZGCommitment, KZGProof
from ethereum.exceptions import (
    EthereumException,
    InvalidSignatureError,
    InvalidTransaction,
)
from ethereum_types.bytes import (
    Bytes,
    Bytes0,
    Bytes8,
    Bytes20,
    Bytes32,
    Bytes48,
    Bytes256,
)
from ethereum_types.numeric import U64, U256, Uint
from hypothesis import HealthCheck, assume, given, settings
from py_ecc.fields import optimized_bls12_381_FQ as BLSF
from py_ecc.fields import optimized_bls12_381_FQ2 as BLSF2
from py_ecc.fields import optimized_bls12_381_FQ12 as BLSF12
from py_ecc.typing import Optimized_Point3D
from starkware.cairo.common.dict import DictManager
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME
from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager

from tests.utils.args_gen import (
    U384,
    AddressAccountDiffEntry,
    BLSPubkey,
    G1Compressed,
    G1Uncompressed,
    Memory,
    Stack,
    StorageDiffEntry,
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
    return Serde(segments, cairo_program.identifiers, dict_manager)


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
            key_type, value_type = instance.__orig_class__.__args__
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

    if isinstance(
        instance,
        (BNF2, BNF12, BNF, BNP, BNP2, BLSF, BLSF2, G1Compressed, BLSPubkey),
    ):
        return instance.__class__

    # Empty sequence
    if not instance:
        return tuple if isinstance(instance, tuple) else list

    # Get all element types
    elem_types = [get_type(x) for x in instance]

    if all(t == BLSF for t in elem_types):
        return Optimized_Point3D[BLSF]

    if all(t == BLSF2 for t in elem_types):
        return Optimized_Point3D[BLSF2]

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


def remove_none_values(b: Any) -> Any:
    """Recursively remove None values from mappings and their nested structures."""
    if isinstance(b, (dict, ChainMap, Mapping)):
        return {k: remove_none_values(v) for k, v in b.items() if v is not None}
    elif isinstance(b, (list, tuple)):
        return type(b)(remove_none_values(x) for x in b)
    elif isinstance(b, set):
        return {remove_none_values(x) for x in b if x is not None}
    return b


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
            Optional[Uint],
            U256,
            Bytes0,
            Bytes8,
            Bytes20,
            Bytes32,
            Optional[Bytes32],
            Optional[Hash32],
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
            Optional[Account],
            Bloom,
            VersionedHash,
            Tuple[VersionedHash, ...],
            Tuple[Address, Uint, Tuple[VersionedHash, ...], U64],
            Union[Bytes0, Address],
            Access,
            Tuple[Access, ...],
            LegacyTransaction,
            AccessListTransaction,
            FeeMarketTransaction,
            BlobTransaction,
            Transaction,
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
            Mapping[Tuple[Address, Bytes32], U256],
            Trie[Tuple[Address, Bytes32], U256],
            Trie[Address, Optional[Account]],
            TransientStorage,
            State,
            Tuple[
                Trie[Address, Optional[Account]], Trie[Tuple[Address, Bytes32], U256]
            ],
            List[
                Tuple[
                    Trie[Address, Optional[Account]],
                    Trie[Tuple[Address, Bytes32], U256],
                ]
            ],
            List[Hash32],
            BlockEnvironment,
            TransactionEnvironment,
            Stack[U256],
            Memory,
            Evm,
            Message,
            List[Tuple[U256, U256]],
            ExtendMemory,
            MessageCallOutput,
            Union[Bytes, LegacyTransaction],
            Union[Bytes, Receipt],
            Union[Bytes, Withdrawal],
            Optional[Union[Bytes, LegacyTransaction]],
            Optional[Union[Bytes, Receipt]],
            Optional[Union[Bytes, Withdrawal]],
            Mapping[Bytes, Optional[Union[Bytes, LegacyTransaction]]],
            Mapping[Bytes, Optional[Union[Bytes, Receipt]]],
            Mapping[Bytes, Optional[Union[Bytes, Withdrawal]]],
            Tuple[Union[Bytes, LegacyTransaction], ...],
            Block,
            List[Block],
            BlockChain,
            Trie[Bytes, Optional[Union[Bytes, LegacyTransaction]]],
            Trie[Bytes, Optional[Union[Bytes, Receipt]]],
            Trie[Bytes, Optional[Union[Bytes, Withdrawal]]],
            U384,
            Optional[U384],
            BNF12,
            BNF2,
            BNF,
            BNP,
            BNP2,
            Mapping[Bytes32, Address],
            Mapping[Hash32, Bytes],
            Mapping[Bytes32, Bytes32],
            BLSFieldElement,
            AddressAccountDiffEntry,
            List[AddressAccountDiffEntry],
            StorageDiffEntry,
            List[StorageDiffEntry],
            BLSF,
            BLSF2,
            KZGCommitment,
            Bytes48,
            Optimized_Point3D[BLSF],
            Optimized_Point3D[BLSF2],
            G1Compressed,
            G1Uncompressed,
            BLSPubkey,
            KZGProof,
            BLSF12,
            Tuple[FQ, FQ2],
            Tuple[Tuple[FQ, FQ2], Tuple[FQ, FQ2]],
        ],
    ):
        assume(no_empty_sequence(b))
        assume(single_evm_parent(b))
        type_ = get_type(b)
        b = remove_none_values(b)
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
            EthereumException,
            Revert,
            StackOverflowError,
            StackUnderflowError,
            InvalidOpcode,
            InvalidSignatureError,
            InvalidTransaction,
            ValueError,
            AssertionError,
        ],
    ):
        base = segments.gen_arg([gen_arg(type(err), err)])
        result = serde.serialize(to_cairo_type(type(err)), base, shift=0)
        assert type(result) is type(err)
        if hasattr(err, "message"):
            assert result.message == err.message

    @pytest.mark.parametrize(
        "error_type",
        [
            EthereumException,
            Revert,
            StackOverflowError,
            StackUnderflowError,
            InvalidOpcode,
        ],
    )
    def test_none_exception(self, to_cairo_type, serde, gen_arg, error_type):
        base = gen_arg(error_type, None)
        result = serde.serialize(to_cairo_type(error_type), base, shift=0)
        assert result is None

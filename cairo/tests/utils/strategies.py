# ruff: noqa: E402

import os
from typing import ForwardRef, Sequence, TypeAlias, Union
from unittest.mock import patch

from eth_keys.datatypes import PrivateKey
from ethereum_types.bytes import Bytes0, Bytes8, Bytes20, Bytes32, Bytes256
from ethereum_types.numeric import U64, U256, FixedUnsigned, Uint
from hypothesis import strategies as st
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

from ethereum.crypto.elliptic_curve import SECP256K1N
from ethereum.exceptions import EthereumException
from tests.utils.args_gen import (
    Environment,
    Evm,
    Memory,
    Message,
    Stack,
    State,
    TransientStorage,
    VersionedHash,
)
from tests.utils.constants import BLOCK_GAS_LIMIT

# Mock the Extended type because hypothesis cannot handle the RLP Protocol
# Needs to be done before importing the types from ethereum.cancun.trie
# trunk-ignore(ruff/F821)
MockExtended: TypeAlias = Union[Sequence["Extended"], bytearray, bytes, Uint, FixedUnsigned, str, bool]  # type: ignore
patch("ethereum.rlp.Extended", MockExtended).start()

from ethereum.cancun.blocks import Header, Log, Receipt, Withdrawal
from ethereum.cancun.fork_types import Account, Address, Bloom, Root
from ethereum.cancun.transactions import (
    AccessListTransaction,
    BlobTransaction,
    FeeMarketTransaction,
    LegacyTransaction,
)
from ethereum.cancun.trie import BranchNode, ExtensionNode, LeafNode, Trie
from ethereum.crypto.hash import Hash32

# Base types
# The EELS uses a Uint type different from U64, but Reth uses U64.
# We use the same strategy for both.
uint4 = st.integers(min_value=0, max_value=2**4 - 1)
uint20 = st.integers(min_value=0, max_value=2**20 - 1)
uint24 = st.integers(min_value=0, max_value=2**24 - 1)
uint64 = st.integers(min_value=0, max_value=2**64 - 1).map(U64)
uint = uint64.map(Uint)
uint128 = st.integers(min_value=0, max_value=2**128 - 1)
felt = st.integers(min_value=0, max_value=DEFAULT_PRIME - 1)
uint256 = st.integers(min_value=0, max_value=2**256 - 1).map(U256)
nibble = st.lists(uint4, max_size=64).map(bytes)

bytes0 = st.binary(min_size=0, max_size=0).map(Bytes0)
bytes8 = st.binary(min_size=8, max_size=8).map(Bytes8)
bytes20 = st.binary(min_size=20, max_size=20).map(Bytes20)
address = bytes20.map(Address)
bytes32 = st.binary(min_size=32, max_size=32).map(Bytes32)
hash32 = bytes32.map(Hash32)
root = bytes32.map(Root)
bytes256 = st.binary(min_size=256, max_size=256).map(Bytes256)
bloom = bytes256.map(Bloom)

# Maximum recursion depth for the recursive strategy to avoid heavy memory usage and health check errors
MAX_RECURSION_DEPTH = int(os.getenv("HYPOTHESIS_MAX_RECURSION_DEPTH", 10))
# Maximum size for sets of addresses and tuples of address and bytes32 to avoid heavy memory usage and health check errors
MAX_ADDRESS_SET_SIZE = int(os.getenv("HYPOTHESIS_MAX_ADDRESS_SET_SIZE", 10))
MAX_STORAGE_KEY_SET_SIZE = int(os.getenv("HYPOTHESIS_MAX_STORAGE_KEY_SET_SIZE", 10))

# See ethereum.rlp.Simple and ethereum.rlp.Extended for the definition of Simple and Extended
simple = st.recursive(
    st.one_of(st.binary()),
    st.lists,
    max_leaves=MAX_RECURSION_DEPTH,
)

extended = st.recursive(
    st.one_of(st.binary(), uint, st.text(), st.booleans()),
    st.lists,
    max_leaves=MAX_RECURSION_DEPTH,
)

small_bytes = st.binary(min_size=0, max_size=256)


def trie_strategy(thing):
    key_type, value_type = thing.__args__

    return st.builds(
        Trie,
        secured=st.booleans(),
        default=st.from_type(value_type),
        _data=st.dictionaries(
            st.from_type(key_type), st.from_type(value_type), max_size=50
        ),
    )


def stack_strategy(thing):
    value_type = thing.__args__[0]
    return st.lists(st.from_type(value_type), min_size=0, max_size=1024).map(
        lambda x: Stack[value_type](x)
    )


from typing import Generic, TypeVar

T1 = TypeVar("T1")
T2 = TypeVar("T2")


class TypedTuple(tuple, Generic[T1, T2]):
    """A tuple that maintains its type information."""

    def __new__(cls, values):
        return super(TypedTuple, cls).__new__(cls, values)


def tuple_strategy(thing):
    types = thing.__args__

    # Handle ellipsis tuples
    if len(types) == 2 and types[1] == Ellipsis:
        return st.tuples(st.from_type(types[0]), st.from_type(types[0])).map(
            lambda x: TypedTuple[types[0], Ellipsis](x)
        )

    return st.tuples(*(st.from_type(t) for t in types)).map(
        lambda x: TypedTuple[tuple(types)](x)
    )


# Versions strategies with less data in collections

memory_lite = (
    st.binary(min_size=0, max_size=128)
    .map(lambda x: x + b"\x00" * ((32 - len(x) % 32) % 32))
    .map(Memory)
)

message_lite = st.builds(
    Message,
    caller=address,
    target=st.one_of(bytes0, address),
    current_target=address,
    gas=uint,
    value=uint256,
    data=st.just(b""),
    code_address=st.none() | address,
    code=st.just(b""),
    depth=uint,
    should_transfer_value=st.booleans(),
    is_static=st.booleans(),
    accessed_addresses=st.just(set()),
    accessed_storage_keys=st.just(set()),
    parent_evm=st.none(),
)

BLOCK_HASHES_LIST = [Hash32(Bytes32(bytes([i] * 32))) for i in range(256)]

environment_lite = st.integers(min_value=0).flatmap(  # Generate block number first
    lambda number: st.builds(
        Environment,
        caller=address,
        block_hashes=st.lists(
            st.sampled_from(BLOCK_HASHES_LIST),
            min_size=min(number, 256),  # number or 256 if number is greater
            max_size=min(number, 256),
        ),
        origin=address,
        coinbase=address,
        number=st.just(Uint(number)),  # Use the same number
        base_fee_per_gas=uint,
        gas_limit=uint,
        gas_price=uint,
        time=uint256,
        prev_randao=bytes32,
        state=st.from_type(State),
        chain_id=uint64,
        excess_blob_gas=uint64,
        blob_versioned_hashes=st.lists(
            st.from_type(VersionedHash), min_size=0, max_size=50
        ).map(tuple),
        transient_storage=st.from_type(TransientStorage),
    )
)

evm_lite = st.builds(
    Evm,
    pc=uint,
    stack=stack_strategy(Stack[U256]),
    memory=memory_lite,
    code=st.just(b""),
    gas_left=st.integers(min_value=0, max_value=BLOCK_GAS_LIMIT).map(Uint),
    env=environment_lite,
    valid_jump_destinations=st.just(set()),
    logs=st.just(()),
    refund_counter=st.just(0),
    running=st.booleans(),
    message=message_lite,
    output=st.just(b""),
    accounts_to_delete=st.just(set()),
    touched_accounts=st.just(set()),
    return_data=st.just(b""),
    error=st.none() | st.from_type(EthereumException),
    accessed_addresses=st.just(set()),
    accessed_storage_keys=st.just(set()),
)


# Generating up to 2**13 bytes of memory is enough for most tests as more would take too long
# in the test runner.
# 2**32 bytes would be the value at which the memory expansion would trigger an OOG
# memory size must be a multiple of 32
memory = (
    st.binary(min_size=0, max_size=2**13)
    .map(lambda x: x + b"\x00" * ((32 - len(x) % 32) % 32))
    .map(Memory)
)

# Create a deferred reference to evm strategy to allow message to reference it without causing a circular dependency
evm_strategy = st.deferred(lambda: evm)

message = st.builds(
    Message,
    caller=address,
    target=st.one_of(bytes0, address),
    current_target=address,
    gas=uint,
    value=uint256,
    data=small_bytes,
    code_address=st.none() | address,
    code=small_bytes,
    depth=uint,
    should_transfer_value=st.booleans(),
    is_static=st.booleans(),
    accessed_addresses=st.sets(address, max_size=MAX_ADDRESS_SET_SIZE),
    accessed_storage_keys=st.sets(
        st.tuples(address, bytes32), max_size=MAX_STORAGE_KEY_SET_SIZE
    ),
    parent_evm=st.none() | evm_strategy,
)

evm = st.builds(
    Evm,
    pc=st.from_type(Uint),
    stack=stack_strategy(Stack[U256]),
    memory=memory,
    code=small_bytes,
    gas_left=st.integers(min_value=0, max_value=BLOCK_GAS_LIMIT).map(Uint),
    env=st.from_type(Environment),
    valid_jump_destinations=st.sets(st.from_type(Uint)),
    logs=st.tuples(st.from_type(Log)),
    refund_counter=st.integers(min_value=0),
    running=st.booleans(),
    message=message,
    output=small_bytes,
    accounts_to_delete=st.sets(st.from_type(Address), max_size=MAX_ADDRESS_SET_SIZE),
    touched_accounts=st.sets(st.from_type(Address), max_size=MAX_ADDRESS_SET_SIZE),
    return_data=small_bytes,
    error=st.none() | st.from_type(EthereumException),
    accessed_addresses=st.sets(st.from_type(Address), max_size=MAX_ADDRESS_SET_SIZE),
    accessed_storage_keys=st.sets(
        st.tuples(st.from_type(Address), st.from_type(Bytes32)),
        max_size=MAX_STORAGE_KEY_SET_SIZE,
    ),
)


# Fork
state = st.lists(bytes20, min_size=0, max_size=MAX_ADDRESS_SET_SIZE).flatmap(
    lambda addresses: st.fixed_dictionaries(
        {
            "_main_trie": st.builds(
                lambda data: Trie(secured=True, default=None, _data=data),
                data=st.fixed_dictionaries(
                    {address: st.from_type(Account) for address in addresses}
                ),
            ),
            "_storage_tries": st.fixed_dictionaries(
                {
                    address: st.builds(
                        lambda data: Trie(secured=True, default=0, _data=data),
                        data=st.dictionaries(bytes32, uint256),
                    )
                    for address in addresses
                },
            ),
            "_snapshots": st.just([]),
            "created_accounts": st.just(set()),
        }
    )
)


private_key = (
    st.integers(min_value=1, max_value=int(SECP256K1N) - 1)
    .map(lambda x: int.to_bytes(x, 32, "big"))
    .map(PrivateKey)
)


def register_type_strategies():
    st.register_type_strategy(U64, uint64)
    st.register_type_strategy(Uint, uint)
    st.register_type_strategy(FixedUnsigned, uint)
    st.register_type_strategy(U256, uint256)
    st.register_type_strategy(Bytes0, bytes0)
    st.register_type_strategy(Bytes8, bytes8)
    st.register_type_strategy(Bytes20, bytes20)
    st.register_type_strategy(Address, address)
    st.register_type_strategy(Bytes32, bytes32)
    st.register_type_strategy(Hash32, hash32)
    st.register_type_strategy(Root, root)
    st.register_type_strategy(Bytes256, bytes256)
    st.register_type_strategy(Bloom, bloom)
    st.register_type_strategy(ForwardRef("Simple"), simple)  # type: ignore
    st.register_type_strategy(ForwardRef("Extended"), extended)  # type: ignore
    st.register_type_strategy(Account, st.builds(Account))
    st.register_type_strategy(Withdrawal, st.builds(Withdrawal))
    st.register_type_strategy(Header, st.builds(Header))
    st.register_type_strategy(Log, st.builds(Log))
    st.register_type_strategy(Receipt, st.builds(Receipt))
    st.register_type_strategy(LegacyTransaction, st.builds(LegacyTransaction))
    st.register_type_strategy(AccessListTransaction, st.builds(AccessListTransaction))
    st.register_type_strategy(FeeMarketTransaction, st.builds(FeeMarketTransaction))
    st.register_type_strategy(BlobTransaction, st.builds(BlobTransaction))
    # See https://github.com/ethereum/execution-specs/issues/1043
    st.register_type_strategy(
        LeafNode,
        st.fixed_dictionaries(
            # Value is either storage value or RLP encoded account
            {"rest_of_key": nibble, "value": st.binary(max_size=32 * 4)}
        ).map(lambda x: LeafNode(**x)),
    )
    # See https://github.com/ethereum/execution-specs/issues/1043
    st.register_type_strategy(
        ExtensionNode,
        st.fixed_dictionaries(
            {"key_segment": nibble, "subnode": st.binary(min_size=32, max_size=32)}
        ).map(lambda x: ExtensionNode(**x)),
    )
    st.register_type_strategy(
        BranchNode,
        st.fixed_dictionaries(
            {
                # 16 subnodes of 32 bytes each
                "subnodes": st.lists(
                    st.binary(min_size=32, max_size=32), min_size=16, max_size=16
                ).map(tuple),
                # Value in branch nodes is always empty
                "value": st.just(b""),
            }
        ).map(lambda x: BranchNode(**x)),
    )
    st.register_type_strategy(PrivateKey, private_key)
    st.register_type_strategy(Trie, trie_strategy)
    st.register_type_strategy(Stack, stack_strategy)
    st.register_type_strategy(Memory, memory)
    st.register_type_strategy(Evm, evm)
    st.register_type_strategy(tuple, tuple_strategy)

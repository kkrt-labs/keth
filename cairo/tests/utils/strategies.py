# ruff: noqa: E402

from dataclasses import fields
from typing import ForwardRef, Sequence, TypeAlias, Union
from unittest.mock import patch

from eth_keys.datatypes import PrivateKey
from ethereum_types.bytes import Bytes0, Bytes8, Bytes20, Bytes32, Bytes256
from ethereum_types.numeric import U64, U256, FixedUnsigned, Uint
from hypothesis import strategies as st
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

from ethereum.crypto.elliptic_curve import SECP256K1N
from ethereum.exceptions import EthereumException
from tests.utils.args_gen import Environment, Evm, Memory, Message, Stack

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

# See ethereum.rlp.Simple and ethereum.rlp.Extended for the definition of Simple and Extended
simple = st.recursive(st.one_of(st.binary()), st.lists)
extended = st.recursive(
    st.one_of(st.binary(), uint, st.text(), st.booleans()), st.lists
)

small_bytes = st.binary(min_size=0, max_size=256).map(bytes)


# See https://github.com/ethereum/execution-specs/issues/1036
# It's currently not possible to generate strategies using `st.builds` because the dataclasses
# use a slotted_freezable decorator that overrides the default __init__ method without wrapping it.
# So we need to redefine all dataclasses here manually instead of using `st.from_type`.
def st_from_type(cls):
    return st.fixed_dictionaries(
        {field.name: st.from_type(field.type) for field in fields(cls)}
    ).map(lambda x: cls(**x))


def trie_strategy(thing):
    key_type, value_type = thing.__args__

    return st.fixed_dictionaries(
        {
            "secured": st.booleans(),
            "default": st.from_type(value_type),
            "_data": st.dictionaries(st.from_type(key_type), st.from_type(value_type)),
        }
    ).map(lambda x: Trie[key_type, value_type](**x))


def stack_strategy(thing):
    value_type = thing.__args__[0]
    return st.lists(st.from_type(value_type), min_size=0, max_size=1024).map(
        lambda x: Stack[value_type](x)
    )


def memory_strategy():
    """
    Generating up to 2**13 bytes of memory is enough for most tests as more would take too long
    in the test runner.
    2**32 bytes would be the value at which the memory expansion would trigger an OOG
    """
    return st.binary(min_size=0, max_size=2**13).map(Memory)


def evm_strategy(_thing):
    return st.fixed_dictionaries(
        {
            "pc": st.from_type(Uint),
            "stack": stack_strategy(Stack[U256]),
            "memory": memory_strategy(),
            "code": small_bytes,
            "gas_left": uint,
            "env": st.from_type(Environment),
            "valid_jump_destinations": st.sets(st.from_type(Uint)),
            "logs": st.tuples(st.from_type(Log)),
            "refund_counter": st.integers(min_value=0),
            "running": st.booleans(),
            "message": st.from_type(Message),
            "output": small_bytes,
            "accounts_to_delete": st.sets(st.from_type(Address)),
            "touched_accounts": st.sets(st.from_type(Address)),
            "return_data": small_bytes,
            "error": st.none() | st.from_type(EthereumException),
            "accessed_addresses": st.sets(st.from_type(Address)),
            "accessed_storage_keys": st.sets(
                st.tuples(st.from_type(Address), st.from_type(Bytes32))
            ),
        }
    ).map(lambda x: Evm(**x))


def message_strategy(_thing):
    return st.fixed_dictionaries(
        {
            "caller": address,
            "target": st.one_of(bytes0, address),
            "current_target": address,
            "gas": uint,
            "value": uint256,
            "data": small_bytes,
            "code_address": st.none() | address,
            "code": small_bytes,
            "depth": uint,
            "should_transfer_value": st.booleans(),
            "is_static": st.booleans(),
            "accessed_addresses": st.sets(address),
            "accessed_storage_keys": st.sets(st.tuples(address, bytes32)),
            "parent_evm": st.none() | evm_strategy(),
        }
    ).map(lambda x: Message(**x))


# Fork
state = st.lists(bytes20).flatmap(
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
    st.register_type_strategy(Account, st_from_type(Account))
    st.register_type_strategy(Withdrawal, st_from_type(Withdrawal))
    st.register_type_strategy(Header, st_from_type(Header))
    st.register_type_strategy(Log, st_from_type(Log))
    st.register_type_strategy(Receipt, st_from_type(Receipt))
    st.register_type_strategy(LegacyTransaction, st_from_type(LegacyTransaction))
    st.register_type_strategy(
        AccessListTransaction, st_from_type(AccessListTransaction)
    )
    st.register_type_strategy(FeeMarketTransaction, st_from_type(FeeMarketTransaction))
    st.register_type_strategy(BlobTransaction, st_from_type(BlobTransaction))
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
    st.register_type_strategy(Memory, memory_strategy)
    st.register_type_strategy(Evm, evm_strategy)

# ruff: noqa: E402

import os
from collections import ChainMap, defaultdict
from typing import (
    ForwardRef,
    Generic,
    Optional,
    Tuple,
    Type,
    TypeVar,
    Union,
    get_args,
    get_origin,
)

from eth_keys.datatypes import PrivateKey
from ethereum.cancun.blocks import Header, Log, Receipt, Withdrawal
from ethereum.cancun.fork_types import Address, Bloom, Root
from ethereum.cancun.transactions import (
    AccessListTransaction,
    BlobTransaction,
    FeeMarketTransaction,
    LegacyTransaction,
)
from ethereum.cancun.trie import (
    BranchNode,
    ExtensionNode,
    LeafNode,
    Trie,
    copy_trie,
)
from ethereum.cancun.trie import root as compute_root
from ethereum.cancun.vm import Environment, Evm, Message
from ethereum.crypto.alt_bn128 import BNF, BNF2, BNF12, BNP, BNP2, BNP12
from ethereum.crypto.elliptic_curve import SECP256K1N
from ethereum.crypto.finite_field import GaloisField
from ethereum.crypto.hash import Hash32
from ethereum.exceptions import EthereumException
from ethereum_types.bytes import (
    Bytes0,
    Bytes4,
    Bytes8,
    Bytes20,
    Bytes32,
    Bytes64,
    Bytes256,
)
from ethereum_types.numeric import U64, U256, FixedUnsigned, Uint
from hypothesis import strategies as st
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

from cairo_ec.curve import AltBn128

# Note: I have noticed that even if we patch the imports in conftests.py, because hypothesis runs before these patches are applied,
# this file would still be working with the old types. Thus, we _explicitly_ import our patched types from args_gen.py here.
from tests.utils.args_gen import (  # noqa
    EMPTY_STORAGE_ROOT,
    U384,
    Account,
    Environment,
    Evm,
    Memory,
    Message,
    MessageCallOutput,
    MutableBloom,
    Stack,
    State,
    TransientStorage,
    VersionedHash,
)
from tests.utils.constants import BLOCK_GAS_LIMIT, MAX_BLOB_GAS_PER_BLOCK

# Base types
# The EELS uses a Uint type different from U64, but Reth uses U64.
# We use the same strategy for both.
uint4 = st.integers(min_value=0, max_value=2**4 - 1)
uint8 = st.integers(min_value=0, max_value=2**8 - 1)
uint20 = st.integers(min_value=0, max_value=2**20 - 1)
uint24 = st.integers(min_value=0, max_value=2**24 - 1)
uint64 = st.integers(min_value=0, max_value=2**64 - 1).map(U64)
uint = uint64.map(Uint)
uint128 = st.integers(min_value=0, max_value=2**128 - 1)
felt = st.integers(min_value=-DEFAULT_PRIME // 2, max_value=DEFAULT_PRIME // 2)
positive_felt = st.integers(min_value=0, max_value=DEFAULT_PRIME - 1)
uint256 = st.integers(min_value=0, max_value=2**256 - 1).map(U256)
uint384 = st.integers(min_value=0, max_value=2**384 - 1).map(U384)
nibble = st.lists(uint4, max_size=64).map(bytes)

bytes0 = st.binary(min_size=0, max_size=0).map(Bytes0)
bytes4 = st.integers(min_value=0, max_value=2**32 - 1).map(
    lambda x: Bytes4(x.to_bytes(4, "little"))
)
bytes8 = st.integers(min_value=0, max_value=2**64 - 1).map(
    lambda x: Bytes8(x.to_bytes(8, "little"))
)
bytes20 = st.integers(min_value=0, max_value=2**160 - 1).map(
    lambda x: Bytes20(x.to_bytes(20, "little"))
)
bytes64 = st.integers(min_value=0, max_value=2**512 - 1).map(
    lambda x: Bytes64(x.to_bytes(64, "little"))
)
address = bytes20.map(Address)
address_zero = Bytes20(b"\x00" * 20)
bytes32 = st.integers(min_value=0, max_value=2**256 - 1).map(
    lambda x: Bytes32(x.to_bytes(32, "little"))
)
hash32 = bytes32.map(Hash32)
root = bytes32.map(Root)
bytes256 = st.integers(min_value=0, max_value=2**2048 - 1).map(
    lambda x: Bytes256(x.to_bytes(256, "little"))
)
bloom = bytes256.map(Bloom)

excess_blob_gas = st.integers(min_value=0, max_value=MAX_BLOB_GAS_PER_BLOCK * 2).map(
    U64
)

# Maximum recursion depth for the recursive strategy to avoid heavy memory usage and health check errors
MAX_RECURSION_DEPTH = int(os.getenv("HYPOTHESIS_MAX_RECURSION_DEPTH", 10))
# Maximum size for sets of addresses and tuples of address and bytes32 to avoid heavy memory usage and health check errors
MAX_ADDRESS_SET_SIZE = int(os.getenv("HYPOTHESIS_MAX_ADDRESS_SET_SIZE", 10))
MAX_STORAGE_KEY_SET_SIZE = int(os.getenv("HYPOTHESIS_MAX_STORAGE_KEY_SET_SIZE", 10))
MAX_JUMP_DESTINATIONS_SET_SIZE = int(
    os.getenv("HYPOTHESIS_MAX_JUMP_DESTINATIONS_SET_SIZE", 10)
)
MAX_CODE_SIZE = int(os.getenv("HYPOTHESIS_MAX_CODE_SIZE", 256))
MAX_MEMORY_SIZE = int(os.getenv("HYPOTHESIS_MAX_MEMORY_SIZE", 256))

MAX_ADDRESS_TRANSIENT_STORAGE_SIZE = int(
    os.getenv("HYPOTHESIS_MAX_ADDRESS_TRANSIENT_STORAGE_SIZE", 10)
)
MAX_TRANSIENT_STORAGE_SNAPSHOTS_SIZE = int(
    os.getenv("HYPOTHESIS_MAX_TRANSIENT_STORAGE_SNAPSHOTS_SIZE", 10)
)
MAX_ACCOUNTS_TO_DELETE_SIZE = int(
    os.getenv("HYPOTHESIS_MAX_ACCOUNTS_TO_DELETE_SIZE", 10)
)
MAX_TOUCHED_ACCOUNTS_SIZE = int(os.getenv("HYPOTHESIS_MAX_TOUCHED_ACCOUNTS_SIZE", 10))
MAX_TUPLE_SIZE = int(os.getenv("HYPOTHESIS_MAX_TUPLE_SIZE", 20))


small_bytes = st.binary(max_size=256)
code = st.binary(max_size=MAX_CODE_SIZE)
pc = st.integers(min_value=0, max_value=MAX_CODE_SIZE * 2).map(Uint)

# See ethereum_rlp.rlp.Simple and ethereum_rlp.rlp.Extended for the definition of Simple and Extended
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


def trie_strategy(thing, min_size=0, include_none=False):
    key_type, value_type = thing.__args__
    value_type_origin = get_origin(value_type) or value_type

    # If the value_type is Optional[T], then the default value is _always_ None in our context
    if value_type_origin is Union and type(None) in get_args(value_type):
        default_strategy = st.none()
    elif value_type is U256:
        default_strategy = st.just(U256(0))
    else:
        default_strategy = st.nothing()

    # Create a strategy for non-default values
    def non_default_strategy(default):
        if default is None and not include_none:
            # For Optional types, just use the base type strategy (which won't generate None)
            defined_types = [t for t in get_args(value_type) if t is not type(None)]
            # random choice of the defined types
            return st.one_of(*(st.from_type(t) for t in defined_types))
        elif default is None and include_none:
            return st.from_type(value_type)
        elif value_type is U256:
            # For U256, we don't want to generate 0 as default value
            return st.integers(min_value=1, max_value=2**256 - 1).map(U256)
        else:
            raise ValueError(f"Unsupported default type in Trie: {value_type}")

    # In a trie, a key that has a default value is considered not included in the trie.
    # Thus it needs to be filtered out from the data generated.
    # All trees are generated secured.
    return default_strategy.flatmap(
        lambda default: st.builds(
            Trie[key_type, value_type],
            secured=st.just(True),
            default=st.just(default),
            _data=st.dictionaries(
                st.from_type(key_type),
                non_default_strategy(default),
                min_size=min_size,
                max_size=15,
            ).map(lambda x: defaultdict(lambda: default, x)),
        )
    )


def stack_strategy(thing, max_size=1024):
    value_type = thing.__args__[0]
    return st.lists(st.from_type(value_type), min_size=0, max_size=max_size).map(
        lambda x: Stack[value_type](x)
    )


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
        return (
            st.lists(st.from_type(types[0]), max_size=MAX_TUPLE_SIZE)
            .map(tuple)
            .map(lambda x: TypedTuple[types](x))
        )

    return st.tuples(*(st.from_type(t) for t in types)).map(
        lambda x: TypedTuple[types](x)
    )


K = TypeVar("K")
V = TypeVar("V")


class TypedDict(dict, Generic[K, V]):
    """A dict that maintains its type information."""

    def __new__(cls, values):
        return super(TypedDict, cls).__new__(cls, values)


def dict_strategy(thing):
    if hasattr(thing, "__args__"):
        # If the thing contains type information, use it
        key_type, value_type = thing.__args__
        return st.dictionaries(st.from_type(key_type), st.from_type(value_type)).map(
            lambda x: TypedDict[key_type, value_type](x)
        )
    else:
        return st.dictionaries()


gas_left = st.integers(min_value=0, max_value=BLOCK_GAS_LIMIT).map(Uint)

accessed_addresses = st.sets(st.from_type(Address), max_size=MAX_ADDRESS_SET_SIZE)
accessed_storage_keys = st.sets(
    st.tuples(address, bytes32), max_size=MAX_STORAGE_KEY_SET_SIZE
)
# Versions strategies with less data in collections
memory_lite_size = 512
memory_lite = (
    st.binary(max_size=memory_lite_size)
    .map(lambda x: x + b"\x00" * ((32 - len(x) % 32) % 32))
    .map(Memory)
)


def bounded_u256_strategy(min_value: int = 0, max_value: int = 2**256 - 1):
    return st.integers(min_value=min_value, max_value=max_value).map(U256)


memory_lite_start_position = bounded_u256_strategy(max_value=memory_lite_size // 2)
memory_lite_access_size = bounded_u256_strategy(max_value=memory_lite_size // 2)
memory_lite_destination = bounded_u256_strategy(max_value=memory_lite_size * 2)


message_lite = st.builds(
    Message,
    caller=address,
    target=st.one_of(bytes0, address),
    current_target=address,
    gas=uint,
    value=uint256,
    data=st.just(b""),
    code_address=st.none() | address,
    code=code,
    depth=uint,
    should_transfer_value=st.booleans(),
    is_static=st.booleans(),
    accessed_addresses=st.builds(set, st.just(set())),
    accessed_storage_keys=st.builds(set, st.just(set())),
    parent_evm=st.none(),
)

# Using this list instead of the hash32 strategy to avoid data_to_large errors
BLOCK_HASHES_LIST = [Hash32(Bytes32(bytes([i] * 32))) for i in range(256)]

transient_storage = st.sets(
    address, max_size=MAX_ADDRESS_TRANSIENT_STORAGE_SIZE
).flatmap(
    lambda addresses: st.builds(
        TransientStorage,
        _tries=st.fixed_dictionaries(
            {
                # min_size = 1 because empty tries are deleted from the Dict[Address,Trie] in EELS
                address: trie_strategy(Trie[Bytes32, U256], min_size=1)
                for address in addresses
            }
        ),
        _snapshots=st.builds(list, st.just([])),  # Start with empty snapshots list
    ).map(
        # Create the original snapshot using copies of the tries
        lambda storage: TransientStorage(
            _tries=storage._tries,
            _snapshots=[
                {addr: copy_trie(trie) for addr, trie in storage._tries.items()}
            ],
        )
    )
)

# Fork
environment_lite = st.integers(
    min_value=0, max_value=2**64 - 1
).flatmap(  # Generate block number first
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
        excess_blob_gas=excess_blob_gas,
        blob_versioned_hashes=st.lists(
            st.from_type(VersionedHash), min_size=0, max_size=5
        ).map(tuple),
        transient_storage=transient_storage,
    )
)

valid_jump_destinations_lite = st.sets(uint, max_size=MAX_JUMP_DESTINATIONS_SET_SIZE)


# Generating up to 2**13 bytes of memory is enough for most tests as more would take too long
# in the test runner.
# 2**32 bytes would be the value at which the memory expansion would trigger an OOG
# memory size must be a multiple of 32
memory_size = 2**13
memory = (
    st.binary(max_size=memory_size)
    .map(lambda x: x + b"\x00" * ((32 - len(x) % 32) % 32))
    .map(Memory)
)
memory_start_position = bounded_u256_strategy(max_value=memory_size // 2)
memory_access_size = bounded_u256_strategy(max_value=memory_size // 2)

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
    code=code,
    depth=uint,
    should_transfer_value=st.booleans(),
    is_static=st.booleans(),
    accessed_addresses=accessed_addresses,
    accessed_storage_keys=accessed_storage_keys,
    parent_evm=st.none() | evm_strategy,
)

evm = st.builds(
    Evm,
    pc=pc,
    stack=stack_strategy(Stack[U256]),
    memory=memory,
    code=code,
    gas_left=gas_left,
    env=st.from_type(Environment),
    valid_jump_destinations=st.sets(st.from_type(Uint)),
    logs=st.from_type(Tuple[Log, ...]),
    refund_counter=felt,
    running=st.booleans(),
    message=message,
    output=small_bytes,
    accounts_to_delete=st.sets(st.from_type(Address), max_size=MAX_ADDRESS_SET_SIZE),
    touched_accounts=st.sets(st.from_type(Address), max_size=MAX_ADDRESS_SET_SIZE),
    return_data=small_bytes,
    error=st.none() | st.from_type(EthereumException),
    accessed_addresses=accessed_addresses,
    accessed_storage_keys=accessed_storage_keys,
)


# Take the EMPTY_STORAGE_ROOT value by default. This will be built in the state strategy, based on the storage tries.
account_strategy = st.builds(
    Account,
    nonce=uint,
    balance=uint256,
    code=code,
    storage_root=st.just(EMPTY_STORAGE_ROOT),
)

# Fork
# A strategy for an empty state - the tries have no data.
empty_state = st.builds(
    State,
    _main_trie=st.builds(
        Trie[Address, Optional[Account]],
        secured=st.just(True),
        default=st.none(),
        _data=st.builds(dict, st.just({})).map(lambda x: defaultdict(lambda: None, x)),
    ),
    _storage_tries=st.builds(dict, st.just({})),
    _snapshots=st.lists(
        st.tuples(
            st.builds(
                Trie[Address, Optional[Account]],
                secured=st.just(True),
                default=st.none(),
                _data=st.builds(dict, st.just({})).map(
                    lambda x: defaultdict(lambda: None, x)
                ),
            ),
            st.builds(dict, st.just({})).map(lambda x: defaultdict(lambda: U256(0), x)),
        ),
        min_size=1,
        max_size=1,
    ),
    created_accounts=st.builds(set, st.just(set())),
)

# https://github.com/ethereum/EIPs/blob/master/EIPS/eip-4788.md
SYSTEM_ADDRESS = Address(
    bytes.fromhex("fffffffffffffffffffffffffffffffffffffffe")  # cspell:disable-line
)
BEACON_ROOTS_ADDRESS = Address(
    bytes.fromhex("000F3df6D732807Ef1319fB7B8bB8522d0Beac02")
)
BEACON_ROOTS_CODE = bytes.fromhex(
    "3373fffffffffffffffffffffffffffffffffffffffe14604d57602036146024575f5ffd5b5f35801560495762001fff810690815414603c575f5ffd5b62001fff01545f5260205ff35b5f5ffd5b62001fff42064281555f359062001fff015500"
)

# Create the special accounts
SYSTEM_ACCOUNT = Account(balance=U256(0), nonce=Uint(0), code=bytes())
BEACON_ROOTS_ACCOUNT = Account(balance=U256(0), nonce=Uint(1), code=BEACON_ROOTS_CODE)


@st.composite
def state_strategy(draw):
    addresses = draw(st.lists(address, max_size=MAX_ADDRESS_SET_SIZE, unique=True))

    # Storage tries are not always present for existing accounts
    # Thus we generate a subset of addresses from the existing accounts
    _storage_tries = draw(
        st.integers(max_value=len(addresses)).flatmap(
            lambda i: st.fixed_dictionaries(
                {
                    address: trie_strategy(Trie[Bytes32, U256], min_size=1)
                    for address in addresses[:i]
                }
            )
        )
    )

    # Ensure the storage root of each account is consistent with the storage tries
    _main_trie = draw(
        st.builds(
            Trie[Address, Optional[Account]],
            secured=st.just(True),
            default=st.none(),
            _data=st.fixed_dictionaries(
                {
                    address: (
                        st.builds(
                            Account,
                            storage_root=st.just(compute_root(_storage_tries[address])),
                        )
                        if address in _storage_tries.keys()
                        else account_strategy
                    )
                    for address in addresses
                }
            ).map(lambda x: defaultdict(lambda: None, x)),
        )
    )

    _snapshots = [
        (
            copy_trie(_main_trie),
            {addr: copy_trie(trie) for addr, trie in _storage_tries.items()},
        )
    ]

    return State(
        _main_trie=_main_trie,
        _storage_tries=_storage_tries,
        _snapshots=_snapshots,
        created_accounts=draw(st.sets(address, max_size=10)),
    )


header = st.builds(
    Header,
    parent_hash=hash32,
    ommers_hash=hash32,
    coinbase=address,
    state_root=root,
    transactions_root=root,
    receipt_root=root,
    bloom=bloom,
    difficulty=uint,
    number=uint,
    gas_limit=uint,
    gas_used=uint,
    timestamp=uint256,
    extra_data=small_bytes,
    prev_randao=bytes32,
    nonce=bytes8,
    base_fee_per_gas=uint,
)


private_key = (
    st.integers(min_value=1, max_value=int(SECP256K1N) - 1)
    .map(lambda x: int.to_bytes(x, 32, "big"))
    .map(PrivateKey)
)


def bnfN_strategy(field: Type[GaloisField], N: int):
    return st.builds(
        field,
        st.lists(
            st.integers(min_value=0, max_value=field.PRIME - 1), min_size=N, max_size=N
        ).map(tuple),
    )


bnf_strategy = st.builds(BNF, st.integers(min_value=0, max_value=BNF.PRIME - 1))
bnf2_strategy = bnfN_strategy(BNF2, 2)
bnf12_strategy = bnfN_strategy(BNF12, 12)

# Point at infinity for BNP12
bnp12_infinity = BNP12(
    BNF12((0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
    BNF12((0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
)


def bnp_generate_valid_point(x):
    g = BNP(1, 2)
    return g.mul_by(x)


# Strategy for BNP points on the curve
bnp_strategy = st.integers(min_value=0, max_value=BNF.PRIME - 1).map(
    lambda x: bnp_generate_valid_point(x)
)


def bnp12_generate_valid_point():
    point = AltBn128.random_point()
    x_coords = (point.x,) + (0,) * 11
    y_coords = (point.y,) + (0,) * 11
    return BNP12(BNF12(x_coords), BNF12(y_coords))


# Strategy for BNP12 points on the curve
bnp12_strategy = st.one_of(
    st.just(bnp12_generate_valid_point()),
    st.just(bnp12_infinity),
)


# Use the the generator for BNP2 with scalar multiplication
# https://eips.ethereum.org/EIPS/eip-197#definition-of-the-groups
def bnp2_generate_valid_point(random_scalar: int):
    g2_x = BNF2(
        (
            10857046999023057135944570762232829481370756359578518086990519993285655852781,
            11559732032986387107991004021392285783925812861821192530917403151452391805634,
        )
    )
    g2_y = BNF2(
        (
            8495653923123431417604973247489272438418190587263600148770280649306958101930,
            4082367875863433681332203403145435568316851327593401208105741076214120093531,
        )
    )
    generator = BNP2(g2_x, g2_y)
    return generator.mul_by(random_scalar)


bnp2_strategy = st.integers(min_value=0, max_value=BNF2.PRIME - 1).map(
    lambda x: bnp2_generate_valid_point(x)
)


def register_type_strategies():
    st.register_type_strategy(U64, uint64)
    st.register_type_strategy(Uint, uint)
    st.register_type_strategy(FixedUnsigned, uint)
    st.register_type_strategy(U256, uint256)
    st.register_type_strategy(U384, uint384)
    st.register_type_strategy(Bytes0, bytes0)
    st.register_type_strategy(Bytes4, bytes4)
    st.register_type_strategy(Bytes8, bytes8)
    st.register_type_strategy(Bytes20, bytes20)
    st.register_type_strategy(Address, address)
    st.register_type_strategy(Bytes32, bytes32)
    st.register_type_strategy(Bytes64, bytes64)
    st.register_type_strategy(Hash32, hash32)
    st.register_type_strategy(Root, root)
    st.register_type_strategy(Bytes256, bytes256)
    st.register_type_strategy(Bloom, bloom)
    st.register_type_strategy(ForwardRef("Simple"), simple)  # type: ignore
    st.register_type_strategy(ForwardRef("Extended"), extended)  # type: ignore
    st.register_type_strategy(Account, account_strategy)
    st.register_type_strategy(Withdrawal, st.builds(Withdrawal))
    st.register_type_strategy(Header, st.builds(Header))
    st.register_type_strategy(Log, st.builds(Log, data=small_bytes))
    st.register_type_strategy(Receipt, st.builds(Receipt))
    st.register_type_strategy(
        LegacyTransaction, st.builds(LegacyTransaction, data=small_bytes)
    )
    st.register_type_strategy(
        AccessListTransaction, st.builds(AccessListTransaction, data=small_bytes)
    )
    st.register_type_strategy(
        FeeMarketTransaction, st.builds(FeeMarketTransaction, data=small_bytes)
    )
    st.register_type_strategy(
        BlobTransaction, st.builds(BlobTransaction, data=small_bytes)
    )
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
            {
                "key_segment": nibble,
                "subnode": st.integers(min_value=0, max_value=2**256 - 1).map(
                    lambda x: x.to_bytes(32, "little")
                ),
            }
        ).map(lambda x: ExtensionNode(**x)),
    )
    st.register_type_strategy(
        BranchNode,
        st.fixed_dictionaries(
            {
                # 16 subnodes of 32 bytes each
                "subnodes": st.lists(
                    st.integers(min_value=0, max_value=2**256 - 1).map(
                        lambda x: x.to_bytes(32, "little")
                    ),
                    min_size=16,
                    max_size=16,
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
    st.register_type_strategy(dict, dict_strategy)
    st.register_type_strategy(ChainMap, dict_strategy)
    st.register_type_strategy(State, state_strategy())
    st.register_type_strategy(TransientStorage, transient_storage)
    st.register_type_strategy(MutableBloom, bloom.map(MutableBloom))
    st.register_type_strategy(Environment, environment_lite)
    st.register_type_strategy(Header, header)
    st.register_type_strategy(
        VersionedHash,
        st.binary(min_size=31, max_size=31).map(lambda x: VersionedHash(b"\x01" + x)),
    )
    st.register_type_strategy(BNF12, bnf12_strategy)
    st.register_type_strategy(BNP12, bnp12_strategy)
    st.register_type_strategy(BNF2, bnf2_strategy)
    st.register_type_strategy(BNF, bnf_strategy)
    st.register_type_strategy(BNP, bnp_strategy)
    st.register_type_strategy(BNP2, bnp2_strategy)

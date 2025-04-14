import functools
from collections import defaultdict
from dataclasses import dataclass, fields, make_dataclass
from typing import (
    ClassVar,
    List,
    Optional,
    Set,
    Tuple,
    TypeVar,
    Union,
)

from ethereum.cancun.blocks import Receipt, Withdrawal
from ethereum.cancun.fork_types import (
    Address,
)
from ethereum.cancun.state import State, TransientStorage
from ethereum.cancun.transactions import (
    LegacyTransaction,
)
from ethereum.cancun.trie import (
    Trie,
    trie_get,
    trie_set,
)
from ethereum.cancun.vm import Environment as EnvironmentBase
from ethereum.cancun.vm import Evm as EvmBase
from ethereum.cancun.vm import Message as MessageBase
from ethereum.cancun.vm.interpreter import MessageCallOutput as MessageCallOutputBase
from ethereum.crypto.hash import Hash32
from ethereum.exceptions import EthereumException
from ethereum_rlp import rlp
from ethereum_types.bytes import (
    Bytes,
    Bytes32,
)
from ethereum_types.frozen import slotted_freezable
from ethereum_types.numeric import U256, FixedUnsigned, Uint, _max_value
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME
from starkware.cairo.lang.vm.crypto import poseidon_hash_many

from cairo_addons.utils.uint256 import int_to_uint256

EMPTY_TRIE_HASH = Hash32.fromhex(
    "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
)
EMPTY_BYTES_HASH = Hash32.fromhex(
    "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
)


class U384(FixedUnsigned):
    """
    Unsigned integer, which can represent `0` to `2 ** 384 - 1`, inclusive.
    """

    MAX_VALUE: ClassVar["U384"]
    """
    Largest value that can be represented by this integer type.
    """

    def __init__(self, value) -> None:
        super().__init__(value)

    # All these operator overloads are required for instantiation of Curve points with int values;
    # because we serialize our types as U384, but the curve
    def __mod__(self, other: Union[int, "U384"]):
        if isinstance(other, U384):
            return U384(self._number % other._number)
        return U384(self._number % other)

    def __add__(self, other: Union[int, "U384"]):
        if isinstance(other, U384):
            return U384(self._number + other._number)
        return U384(self._number + other)

    def __mul__(self, other: Union[int, "U384"]):
        if isinstance(other, U384):
            return U384(self._number * other._number)
        return U384(self._number * other)

    def __sub__(self, other: Union[int, "U384"]):
        if isinstance(other, U384):
            return U384(self._number - other._number)
        return U384(self._number - other)


U384.MAX_VALUE = _max_value(U384, 384)


# In EELS, this is a NewType of int.
# Which cannot be found by isinstance(instance, G1Compressed)
class G1Compressed(int):
    pass


class BLSPubkey(bytes):
    pass


class Memory(bytearray):
    pass


class MutableBloom(bytearray):
    pass


T = TypeVar("T")


class Stack(List[T]):
    MAX_SIZE = 1024

    def push_or_replace(self, value: T):
        if len(self) >= self.MAX_SIZE:
            self.pop()
        self.append(value)

    def push_or_replace_many(self, values: List[T]):
        if len(self) + len(values) > self.MAX_SIZE:
            del self[self.MAX_SIZE - len(values) :]
        self.extend(values)


# All these classes are auto-patched in test imports in cairo/tests/conftests.py
@dataclass
class Environment(
    make_dataclass(
        "Environment",
        [(f.name, f.type, f) for f in fields(EnvironmentBase) if f.name != "traces"],
        namespace={"__doc__": EnvironmentBase.__doc__},
    )
):
    def __eq__(self, other):
        return all(
            getattr(self, field.name) == getattr(other, field.name)
            for field in fields(self)
        )

    @functools.wraps(EnvironmentBase.__init__)
    def __init__(self, *args, **kwargs):
        if "traces" in kwargs:
            del kwargs["traces"]
        super().__init__(*args, **kwargs)

    @property
    def traces(self):
        return []


@dataclass
class MessageCallOutput(
    make_dataclass(
        "MessageCallOutput",
        [(f.name, f.type, f) for f in fields(MessageCallOutputBase)],
        namespace={"__doc__": MessageCallOutputBase.__doc__},
    )
):
    def __eq__(self, other):
        return all(
            getattr(self, field.name) == getattr(other, field.name)
            for field in fields(self)
            if field.name != "error"
        ) and type(self.error) is type(other.error)


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
    def __eq__(self, other):
        common_fields = all(
            getattr(self, field.name) == getattr(other, field.name)
            for field in fields(self)
            if field.name != "parent_evm"
        )
        return common_fields and self.parent_evm == other.parent_evm


@slotted_freezable
@dataclass
class Account:
    # Order of fields is important regarding serde logic
    nonce: Uint
    balance: U256
    code_hash: Hash32
    storage_root: Hash32
    code: bytes

    # Important note: As our cairo computations does not update the storage root, we do not want to use it in the equality checks,
    # as it will always be different from the EELS ones.
    def __eq__(self, other):
        if not isinstance(other, Account):
            return False
        return all(
            getattr(self, field.name) == getattr(other, field.name)
            for field in fields(self)
            if field.name != "storage_root"
        )

    def hash_args(self, with_storage_root: bool = True) -> List[int]:
        """
        Returns the list of arguments used when hashing the account.
        """
        return [
            int(self.nonce),
            *int_to_uint256(int(self.balance)),
            *int_to_uint256(int.from_bytes(self.code_hash, "little")),
            *(
                int_to_uint256(int.from_bytes(self.storage_root, "little"))
                if with_storage_root
                else []
            ),
        ]

    @staticmethod
    def from_rlp(bytes: Bytes) -> "Account":
        """
        Decode the RLP encoded representation of an account.
        Because the RLP encoding does not contain the code, it is initially None.
        """
        decoded = rlp.decode(bytes)
        return Account(
            nonce=Uint(int.from_bytes(decoded[0], "big")),
            balance=U256(int.from_bytes(decoded[1], "big")),
            storage_root=Hash32(decoded[2]),
            code_hash=Hash32(decoded[3]),
            code=None,
        )

    def to_rlp(self) -> Bytes:
        """
        Encode the account as RLP.
        """
        nonce_bytes = (
            self.nonce._number.to_bytes(
                (self.nonce._number.bit_length() + 7) // 8, "big"
            )
            or b"\x00"
        )
        balance_bytes = self.balance._number.to_bytes(32, "big")
        balance_bytes = balance_bytes.lstrip(b"\x00") or b"\x00"

        encoded = rlp.encode(
            [
                nonce_bytes,
                balance_bytes,
                self.storage_root,
                self.code_hash,
            ]
        )
        return encoded


def encode_account(raw_account_data: Account, storage_root: Bytes) -> Bytes:
    from ethereum_rlp import rlp

    return rlp.encode(
        (
            raw_account_data.nonce,
            raw_account_data.balance,
            storage_root,
            # Modified to use code_hash instead of hash(code)
            raw_account_data.code_hash,
        )
    )


# TODO PR in EELS?
def is_account_alive(state: State, address: Address) -> bool:
    from ethereum.cancun.state import get_account_optional

    account = get_account_optional(state, address)
    if account is None:
        return False
    else:
        # Modified to use EMPTY_ACCOUNT - we want to make sure the storage root and code_hash are
        # empty.
        # Remember: Account__eq__ does not take into account the storage root.
        return (
            not account == EMPTY_ACCOUNT or not account.storage_root == EMPTY_TRIE_HASH
        )


def set_code(state: State, address: Address, code: Bytes) -> None:
    from ethereum.cancun.state import modify_state

    def write_code(sender: Account) -> None:
        from ethereum.crypto.hash import keccak256

        sender.code = code
        # Modified to set the code hash as well
        sender.code_hash = keccak256(code)

    modify_state(state, address, write_code)


EMPTY_ACCOUNT = Account(
    nonce=Uint(0),
    balance=U256(0),
    storage_root=EMPTY_TRIE_HASH,
    code_hash=EMPTY_BYTES_HASH,
    code=b"",
)


# Re-definition of the Node type to be used in the tests.
# This is required for the `encode_node` function in `ethereum.cancun.trie` to work.
Node = Union[Account, Bytes, LegacyTransaction, Receipt, Uint, U256, Withdrawal, None]

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
        common_fields_ok = all(
            getattr(self, field.name) == getattr(other, field.name)
            for field in fields(self)
            if field.name != "error" and field.name != "refund_counter"
        ) and type(self.error) is type(other.error)

        # The refund_counter is a felt, is serialized as a positive integer `int`, but in this specific case,
        # we want a felt (that can be either positive or negative)
        refund_counter_ok = (
            self.refund_counter % DEFAULT_PRIME == other.refund_counter % DEFAULT_PRIME
        )
        return common_fields_ok and refund_counter_ok


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
        # Ensure that the dictionary type generated by args_gen is the same as the original one.
        use_defaultdict = isinstance(state._storage_tries, defaultdict)
        flat_state = cls(
            _main_trie=state._main_trie,
            _storage_tries=Trie(
                secured=True,
                default=U256(0),
                _data=defaultdict(lambda: U256(0)) if use_defaultdict else {},
            ),
            _snapshots=[],
            created_accounts=state.created_accounts,
        )

        # Flatten storage tries
        for address, storage_trie in state._storage_tries.items():
            for key in storage_trie._data.keys():
                # Explicitly avoid using `trie_set`, as setting a `0` value will erase the entry.
                # We want to keep the entry, even if the value is `0`, to produce state diffs.
                value = trie_get(storage_trie, key)
                flat_state._storage_tries._data[(address, key)] = value

        # Flatten snapshots
        for snapshot in state._snapshots:
            snapshot_main_trie = snapshot[0]
            snapshot_storage_tries = Trie(
                secured=flat_state._storage_tries.secured,
                default=flat_state._storage_tries.default,
                _data=defaultdict(lambda: U256(0)) if use_defaultdict else {},
            )
            for address, storage_trie in snapshot[1].items():
                for key in storage_trie._data.keys():
                    value = trie_get(storage_trie, key)
                    # Explicitly avoid using `trie_set`, as setting a `0` value will erase the entry.
                    # We want to keep the entry, even if the value is `0`, to produce state diffs.
                    snapshot_storage_tries._data[(address, key)] = value
            flat_state._snapshots.append((snapshot_main_trie, snapshot_storage_tries))

        return flat_state

    def to_state(self) -> State:
        """Convert a FlatState object back to a State object."""
        # Initialize state with main trie and created accounts
        use_defaultdict = isinstance(self._storage_tries, defaultdict)
        state = State(
            _main_trie=self._main_trie,
            _storage_tries=(
                defaultdict(
                    lambda: Trie(
                        secured=True,
                        default=U256(0),
                        _data=defaultdict(lambda: U256(0)),
                    )
                )
                if use_defaultdict
                else {}
            ),
            _snapshots=[],
            created_accounts=self.created_accounts,
        )

        # Unflatten storage tries by grouping by address
        for (address, key), value in self._storage_tries._data.items():
            if address not in state._storage_tries:
                state._storage_tries[address] = Trie(
                    secured=self._storage_tries.secured,
                    default=U256(0),
                    _data=defaultdict(lambda: U256(0)) if use_defaultdict else {},
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
                        _data=defaultdict(lambda: U256(0)) if use_defaultdict else {},
                    )
                trie = address_to_storage_trie[address]
                trie_set(trie, key, value)
                address_to_storage_trie[address] = trie
            state._snapshots.append((snapshot_main_trie, address_to_storage_trie))

        return state


@dataclass
class AddressAccountDiffEntry:
    key: Address
    prev_value: Optional[Account]
    new_value: Account

    def hash_poseidon(self):
        return poseidon_hash_many(
            [
                int.from_bytes(self.key, "little"),
                *(self.prev_value.hash_args() if self.prev_value else []),
                # We don't hash the new storage_root, as we can't compute it from the partial state changes
                *self.new_value.hash_args(with_storage_root=False),
            ]
        )


@dataclass
class StorageDiffEntry:
    key: Uint
    prev_value: U256
    new_value: U256

    def hash_poseidon(self):
        return poseidon_hash_many(
            [
                int(self.key),
                *int_to_uint256(int(self.prev_value)),
                *int_to_uint256(int(self.new_value)),
            ]
        )


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
            _tries=Trie(
                secured=True,
                default=U256(0),
                _data=defaultdict(lambda: U256(0), {}),
            ),
            _snapshots=[],
        )

        # Flatten tries
        for address, storage_trie in ts._tries.items():
            for key in storage_trie._data.keys():
                value = trie_get(storage_trie, key)
                trie_set(flat_ts._tries, (address, key), value)

        # Flatten snapshots
        for snapshot in ts._snapshots:
            snapshot_tries = Trie(
                flat_ts._tries.secured,
                flat_ts._tries.default,
                defaultdict(lambda: U256(0), {}),
            )
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

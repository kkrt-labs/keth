from ethereum.cancun.fork_types import Address
from ethereum.cancun.state import TransientStorage
from ethereum.cancun.vm import BlockEnvironment, Message, TransactionEnvironment
from ethereum.crypto.hash import Hash32
from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U64, U256, Uint
from hypothesis import strategies as st

from tests.utils.strategies import (
    accessed_addresses,
    accessed_storage_keys,
    address_zero,
    block_environment_lite,
    code,
    empty_state,
    gas_left,
    small_bytes,
    transaction_environment_lite,
)

empty_block_environment = st.builds(
    BlockEnvironment,
    chain_id=st.just(U64(0)),
    state=empty_state,
    block_gas_limit=st.just(Uint(0)),
    block_hashes=st.just([]),  # List[Hash32]
    coinbase=st.just(address_zero),
    number=st.just(Uint(0)),
    base_fee_per_gas=st.just(Uint(0)),
    time=st.just(U256(0)),
    prev_randao=st.just(Bytes32(b"\x00" * 32)),
    excess_blob_gas=st.just(U64(0)),
    parent_beacon_block_root=st.just(Hash32(Bytes32(b"\x00" * 32))),
)

empty_transaction_environment = st.builds(
    TransactionEnvironment,
    origin=st.just(address_zero),
    gas_price=st.just(Uint(0)),
    gas=st.just(Uint(0)),
    access_list_addresses=st.just(set()),  # Set[Address]
    access_list_storage_keys=st.just(set()),  # Set[Tuple[Address, Bytes32]]
    transient_storage=st.just(TransientStorage()),
    blob_versioned_hashes=st.just(tuple()),  # Tuple[VersionedHash, ...]
    index_in_block=st.just(None),  # Optional[Uint]
    tx_hash=st.just(None),  # Optional[Hash32]
)


class MessageBuilder:

    def __init__(self):
        self._block_env = empty_block_environment
        self._tx_env = empty_transaction_environment
        self._caller = st.just(address_zero)
        self._target = st.just(address_zero)
        self._current_target = st.just(address_zero)
        self._gas = st.just(Uint(0))
        self._value = st.just(U256(0))
        self._data = st.just(b"")
        self._code_address = st.none()
        self._code = st.just(b"")
        self._depth = st.just(Uint(0))
        self._should_transfer_value = st.just(False)
        self._is_static = st.just(False)
        self._accessed_addresses = st.builds(set, st.just(set()))
        self._accessed_storage_keys = st.builds(set, st.just(set()))
        self._parent_evm = st.none()

    def with_caller(self, strategy=st.from_type(Address)):
        self._caller = strategy
        return self

    def with_target(self, strategy=st.from_type(Address)):
        self._target = strategy
        return self

    def with_current_target(self, strategy=st.from_type(Address)):
        self._current_target = strategy
        return self

    def with_gas(self, strategy=gas_left):
        self._gas = strategy
        return self

    def with_value(self, strategy=st.from_type(U256)):
        self._value = strategy
        return self

    def with_data(self, strategy=small_bytes):
        self._data = strategy
        return self

    def with_code_address(self, strategy=st.from_type(Address) | st.none()):
        self._code_address = strategy
        return self

    def with_code(self, strategy=code):
        self._code = strategy
        return self

    # Restricted to 0-1023 because EELS has an extra, unrequired check on the stack depth
    # in `process_message` which cannot trigger, because `generic_call` and `generic_create`
    # check the stack depth limit before calling `process_message`.
    def with_depth(self, strategy=st.integers(min_value=0, max_value=1023).map(Uint)):
        self._depth = strategy
        return self

    def with_should_transfer_value(self, strategy=st.booleans()):
        self._should_transfer_value = strategy
        return self

    def with_is_static(self, strategy=st.booleans()):
        self._is_static = strategy
        return self

    def with_accessed_addresses(self, strategy=accessed_addresses):
        self._accessed_addresses = strategy
        return self

    def with_accessed_storage_keys(self, strategy=accessed_storage_keys):
        self._accessed_storage_keys = strategy
        return self

    def with_parent_evm(self, strategy=st.none()):
        self._parent_evm = strategy
        return self

    def with_block_env(self, strategy=block_environment_lite):
        self._block_env = strategy
        return self

    def with_tx_env(self, strategy=transaction_environment_lite):
        self._tx_env = strategy
        return self

    def build(self):
        return st.builds(
            Message,
            block_env=self._block_env,
            tx_env=self._tx_env,
            caller=self._caller,
            target=self._target,
            current_target=self._current_target,
            gas=self._gas,
            value=self._value,
            data=self._data,
            code_address=self._code_address,
            code=self._code,
            depth=self._depth,
            should_transfer_value=self._should_transfer_value,
            is_static=self._is_static,
            accessed_addresses=self._accessed_addresses,
            accessed_storage_keys=self._accessed_storage_keys,
            parent_evm=self._parent_evm,
        )

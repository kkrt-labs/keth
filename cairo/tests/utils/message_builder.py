from ethereum_types.numeric import U256, Optional, Uint
from hypothesis import strategies as st

from ethereum.cancun.fork_types import Address
from tests.utils.args_gen import Message
from tests.utils.strategies import (
    accessed_addresses,
    accessed_storage_keys,
    address_zero,
    code,
    gas_left,
    small_bytes,
    uint,
)


class MessageBuilder:

    def __init__(self):
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
        self._accessed_addresses = st.just(set())
        self._accessed_storage_keys = st.just(set())
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

    def with_code_address(self, strategy=st.from_type(Optional[Address])):
        self._code_address = strategy
        return self

    def with_code(self, strategy=code):
        self._code = strategy
        return self

    def with_depth(self, strategy=uint):
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

    def build(self):
        return st.builds(
            Message,
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

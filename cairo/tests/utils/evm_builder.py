from typing import Tuple

from ethereum.exceptions import EthereumException
from ethereum.prague.blocks import Log
from ethereum.prague.fork_types import Address
from ethereum.prague.vm import Evm
from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U256, Uint
from hypothesis import strategies as st

from tests.utils.args_gen import Stack
from tests.utils.message_builder import MessageBuilder
from tests.utils.strategies import (
    MAX_ACCOUNTS_TO_DELETE_SIZE,
    Memory,
    code,
    gas_left,
    memory_lite,
    message_lite,
    stack_strategy,
    uint,
    valid_jump_destinations_lite,
)


class EvmBuilder:
    """Builder pattern for creating EVM hypothesis strategies."""

    def __init__(self):
        self._pc = st.just(Uint(0))
        self._stack = st.builds(list, st.just([])).map(lambda x: Stack[U256](x))
        self._memory = st.builds(Memory, st.just(b""))
        self._code = st.just(b"")
        self._gas_left = st.just(Uint(0))
        self._valid_jump_destinations = st.builds(set, st.just(set()))
        self._logs = st.just(())
        self._refund_counter = st.just(0)
        self._running = st.just(True)
        self._message = MessageBuilder().build()  # empty message
        self._output = st.just(b"")
        self._accounts_to_delete = st.builds(set, st.just(set()))
        self._return_data = st.just(b"")
        self._error = st.none() | st.from_type(EthereumException)
        self._accessed_addresses = st.builds(set, st.just(set()))
        self._accessed_storage_keys = st.builds(set, st.just(set()))

    def with_pc(self, strategy=uint):
        self._pc = strategy
        return self

    def with_stack(self, strategy=stack_strategy(Stack[U256])):
        self._stack = strategy
        return self

    def with_capped_values_stack(self, max_value=2**8 - 1):
        self._stack = st.lists(
            st.integers(min_value=0, max_value=max_value).map(U256),
            min_size=0,
            max_size=1024,
        ).map(lambda x: Stack[U256](x))
        return self

    def with_memory(self, strategy=memory_lite):
        self._memory = strategy
        return self

    def with_code(self, strategy=code):
        self._code = strategy
        return self

    def with_gas_left(self, strategy=gas_left):
        self._gas_left = strategy
        return self

    def with_message(self, strategy=message_lite):
        self._message = strategy
        return self

    def with_valid_jump_destinations(self, strategy=valid_jump_destinations_lite):
        self._valid_jump_destinations = strategy
        return self

    def with_running(self, strategy=st.booleans()):
        self._running = strategy
        return self

    def with_accessed_addresses(
        self, strategy=st.sets(st.from_type(Address), max_size=10)
    ):
        self._accessed_addresses = strategy
        return self

    def with_accessed_storage_keys(
        self, strategy=st.sets(st.from_type(Tuple[Address, Bytes32]), max_size=10)
    ):
        self._accessed_storage_keys = strategy
        return self

    def with_return_data(self, strategy=st.binary(min_size=0, max_size=1024)):
        self._return_data = strategy
        return self

    def with_logs(self, strategy=st.from_type(Tuple[Log, ...])):
        self._logs = strategy
        return self

    def with_accounts_to_delete(
        self,
        strategy=st.sets(st.from_type(Address), max_size=MAX_ACCOUNTS_TO_DELETE_SIZE),
    ):
        self._accounts_to_delete = strategy
        return self

    def with_refund_counter(
        self, strategy=st.integers(min_value=-(2**64) - 1, max_value=2**64)
    ):
        self._refund_counter = strategy
        return self

    def build(self):
        return st.builds(
            Evm,
            pc=self._pc,
            stack=self._stack,
            memory=self._memory,
            code=self._code,
            gas_left=self._gas_left,
            valid_jump_destinations=self._valid_jump_destinations,
            logs=self._logs,
            refund_counter=self._refund_counter,
            running=self._running,
            message=self._message,
            output=self._output,
            accounts_to_delete=self._accounts_to_delete,
            return_data=self._return_data,
            error=self._error,
            accessed_addresses=self._accessed_addresses,
            accessed_storage_keys=self._accessed_storage_keys,
        )

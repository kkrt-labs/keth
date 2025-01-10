from ethereum_types.bytes import Bytes20
from ethereum_types.numeric import U64, U256, Bytes32, Uint
from hypothesis import strategies as st

from ethereum.cancun.state import State, TransientStorage
from ethereum.exceptions import EthereumException
from tests.utils.args_gen import Environment, Evm, Message, Stack
from tests.utils.strategies import (
    Memory,
    environment_lite,
    gas_left,
    memory_lite,
    message_lite,
    small_bytes,
    stack_strategy,
    uint,
    valid_jump_destinations_lite,
)

address_zero = Bytes20(b"\x00" * 20)

empty_environment = st.builds(
    Environment,
    caller=st.just(address_zero),
    block_hashes=st.just([]),
    origin=st.just(address_zero),
    coinbase=st.just(address_zero),
    number=st.just(Uint(0)),
    base_fee_per_gas=st.just(Uint(0)),
    gas_limit=st.just(Uint(0)),
    gas_price=st.just(Uint(0)),
    time=st.just(U256(0)),
    prev_randao=st.just(Bytes32(b"\x00" * 32)),
    state=st.just(State()),
    chain_id=st.just(U64(0)),
    excess_blob_gas=st.just(U64(0)),
    blob_versioned_hashes=st.just(()),
    transient_storage=st.just(TransientStorage()),
)

empty_message = st.builds(
    Message,
    caller=st.just(address_zero),
    target=st.just(address_zero),
    current_target=st.just(address_zero),
    gas=st.just(Uint(0)),
    value=st.just(U256(0)),
    data=st.just(b""),
    code_address=st.none(),
    code=st.just(b""),
    depth=st.just(Uint(0)),
    should_transfer_value=st.just(False),
    is_static=st.just(False),
    accessed_addresses=st.just(set()),
    accessed_storage_keys=st.just(set()),
    parent_evm=st.none(),
)


class EvmBuilder:
    """Builder pattern for creating EVM hypothesis strategies."""

    def __init__(self):
        self._pc = st.just(Uint(0))
        self._stack = st.just([])
        self._memory = st.just(Memory(b""))
        self._code = st.just(b"")
        self._gas_left = st.just(Uint(0))
        self._env = empty_environment
        self._valid_jump_destinations = st.just(set())
        self._logs = st.just(())
        self._refund_counter = st.just(0)
        self._running = st.just(True)
        self._message = empty_message
        self._output = st.just(b"")
        self._accounts_to_delete = st.just(set())
        self._touched_accounts = st.just(set())
        self._return_data = st.just(b"")
        self._error = st.none() | st.from_type(EthereumException)
        self._accessed_addresses = st.just(set())
        self._accessed_storage_keys = st.just(set())

    def with_pc(self, strategy=uint):
        self._pc = strategy
        return self

    def with_stack(self, strategy=stack_strategy(Stack[U256])):
        self._stack = strategy
        return self

    def with_memory(self, strategy=memory_lite):
        self._memory = strategy
        return self

    def with_code(self, strategy=small_bytes):
        self._code = strategy
        return self

    def with_gas_left(self, strategy=gas_left):
        self._gas_left = strategy
        return self

    def with_env(self, strategy=environment_lite):
        self._env = strategy
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

    def build(self):
        return st.builds(
            Evm,
            pc=self._pc,
            stack=self._stack,
            memory=self._memory,
            code=self._code,
            gas_left=self._gas_left,
            env=self._env,
            valid_jump_destinations=self._valid_jump_destinations,
            logs=self._logs,
            refund_counter=self._refund_counter,
            running=self._running,
            message=self._message,
            output=self._output,
            accounts_to_delete=self._accounts_to_delete,
            touched_accounts=self._touched_accounts,
            return_data=self._return_data,
            error=self._error,
            accessed_addresses=self._accessed_addresses,
            accessed_storage_keys=self._accessed_storage_keys,
        )

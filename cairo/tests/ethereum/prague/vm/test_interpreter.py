import pytest
from ethereum.prague.fork_types import Address
from ethereum.prague.vm import (
    Message,
)
from ethereum.prague.vm.interpreter import (
    execute_code,
    process_create_message,
    process_message,
    process_message_call,
)
from ethereum_types.bytes import Bytes, Bytes20
from hypothesis import given
from hypothesis import strategies as st

from cairo_addons.testing.errors import strict_raises
from tests.utils.message_builder import MessageBuilder
from tests.utils.strategies import block_environment_lite, transaction_environment_lite

message_strategy = (
    MessageBuilder()
    .with_block_env(block_environment_lite)
    .with_tx_env(transaction_environment_lite)
    .with_current_target(
        st.integers(min_value=0, max_value=2**160 - 1)
        .map(lambda x: Bytes20(x.to_bytes(20, "little")))
        .map(Address)
    )
    .with_caller()
    .with_gas()
    .with_value()
    .with_data()
    .with_code_address(st.from_type(Address))
    .with_depth()
    .with_code(
        strategy=st.just(Bytes(bytes.fromhex("6060")))
    )  # TODO: generate code with random opcodes
    .with_accessed_addresses()
    .with_accessed_storage_keys()
    .build()
)


class TestInterpreter:
    @given(
        message=message_strategy,
    )
    @pytest.mark.slow
    def test_execute_code(self, cairo_run, message: Message):
        try:
            evm_cairo = cairo_run("execute_code", message)
        except Exception as e:
            with strict_raises(type(e)):
                execute_code(message)
            return

        evm_python = execute_code(message)
        assert evm_python == evm_cairo

    @given(
        message=message_strategy,
    )
    @pytest.mark.slow
    def test_process_message(self, cairo_run, message: Message):
        try:
            evm_cairo = cairo_run("process_message", message)
        except Exception as e:
            with strict_raises(type(e)):
                process_message(message)
            return

        evm_python = process_message(message)
        assert evm_python == evm_cairo

    @given(
        message=message_strategy,
    )
    @pytest.mark.slow
    def test_process_create_message(self, cairo_run, message: Message):
        try:
            evm_cairo = cairo_run("process_create_message", message)
        except Exception as e:
            with strict_raises(type(e)):
                process_create_message(message)
            return

        evm_python = process_create_message(message)
        assert evm_python == evm_cairo

    @given(
        message=message_strategy,
    )
    @pytest.mark.slow
    def test_process_message_call(self, cairo_run, message: Message):
        # Explicitly clean any snapshot in the state - as in the initial state of a tx, there are no snapshots.
        # This only applies to the entrypoint of a transaction.
        message.block_env.state._snapshots = []
        try:
            _, messageCallOutput = cairo_run("process_message_call", message)
        except Exception as e:
            with strict_raises(type(e)):
                process_message_call(message)
            return

        assert messageCallOutput == process_message_call(message)

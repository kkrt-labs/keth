from ethereum_types.bytes import Bytes, Bytes20
from hypothesis import given
from hypothesis import strategies as st

from ethereum.cancun.fork_types import Address
from ethereum.cancun.vm import Environment, Message
from ethereum.cancun.vm.interpreter import (
    execute_code,
    process_create_message,
    process_message,
)
from tests.utils.errors import strict_raises
from tests.utils.message_builder import MessageBuilder
from tests.utils.strategies import environment_lite

message_without_precompile = (
    MessageBuilder()
    .with_current_target(
        st.integers(min_value=11, max_value=2**160 - 1)
        .map(lambda x: Bytes20(x.to_bytes(20, "little")))
        .map(Address)
    )
    .with_caller()
    .with_gas()
    .with_value()
    .with_data()
    .with_code_address()
    .with_code(
        strategy=st.just(Bytes(bytes.fromhex("6060")))
    )  # TODO: generate code with random opcodes
    .with_accessed_addresses()
    .with_accessed_storage_keys()
    .build()
)


class TestInterpreter:
    @given(
        message=message_without_precompile,
        env=environment_lite,
    )
    def test_execute_code(self, cairo_run, message: Message, env: Environment):
        try:
            evm_cairo = cairo_run("execute_code", message, env)
        except Exception as e:
            with strict_raises(type(e)):
                execute_code(message, env)
            return

        evm_python = execute_code(message, env)
        assert evm_python == evm_cairo

    @given(
        message=message_without_precompile,
        env=environment_lite,
    )
    def test_process_message(self, cairo_run, message: Message, env: Environment):
        try:
            evm_cairo = cairo_run("process_message", message, env)
        except Exception as e:
            with strict_raises(type(e)):
                process_message(message, env)
            return

        evm_python = process_message(message, env)
        assert evm_python == evm_cairo

    @given(
        message=message_without_precompile,
        env=environment_lite,
    )
    def test_process_create_message(
        self, cairo_run, message: Message, env: Environment
    ):
        try:
            evm_cairo = cairo_run("process_create_message", message, env)
        except Exception as e:
            with strict_raises(type(e)):
                process_create_message(message, env)
            return

        evm_python = process_create_message(message, env)
        assert evm_python == evm_cairo

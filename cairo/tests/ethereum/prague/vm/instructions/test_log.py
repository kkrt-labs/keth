from ethereum.exceptions import EthereumException
from ethereum.prague.vm import Evm
from ethereum.prague.vm.instructions.log import log0, log1, log2, log3, log4
from ethereum_types.numeric import U256
from hypothesis import given
from hypothesis.strategies import composite, integers

from cairo_addons.testing.errors import strict_raises
from tests.utils.args_gen import Stack
from tests.utils.evm_builder import EvmBuilder
from tests.utils.message_builder import MessageBuilder
from tests.utils.strategies import (
    memory_lite_access_size,
    memory_lite_start_position,
    stack_strategy,
    uint256,
)


@composite
def log_strategy(draw, num_topics: int):
    """Generate test cases for the log instructions.

    This strategy generates an EVM instance and the required parameters for log operations.
    - 8/10 chance: pushes all parameters onto the stack to test normal operation
    - 2/10 chance: use stack already populated with values, mostly to test error cases

    Args:
        num_topics: Number of topics for the log operation (0-4)
    """
    evm = draw(
        EvmBuilder()
        .with_stack(stack_strategy(Stack[U256], max_size=128))
        .with_gas_left()
        .with_memory()
        .with_message(MessageBuilder().with_is_static().build())
        .build()
    )
    start_index = draw(memory_lite_start_position)
    size = draw(memory_lite_access_size)
    topics = [draw(uint256) for _ in range(num_topics)]

    # 80% chance to push valid values onto stack
    should_push = draw(integers(0, 99)) < 80
    if should_push:
        evm.stack.push_or_replace_many([start_index, size])
        for topic in reversed(topics):
            evm.stack.push_or_replace(topic)

    return evm


class TestLog:
    @given(evm=log_strategy(num_topics=0))
    def test_log0(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("log0", evm)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                log0(evm)
            return

        log0(evm)
        assert evm == cairo_result

    @given(evm=log_strategy(num_topics=1))
    def test_log1(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("log1", evm)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                log1(evm)
            return

        log1(evm)
        assert evm == cairo_result

    @given(evm=log_strategy(num_topics=2))
    def test_log2(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("log2", evm)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                log2(evm)
            return

        log2(evm)
        assert evm == cairo_result

    @given(evm=log_strategy(num_topics=3))
    def test_log3(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("log3", evm)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                log3(evm)
            return

        log3(evm)
        assert evm == cairo_result

    @given(evm=log_strategy(num_topics=4))
    def test_log4(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("log4", evm)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                log4(evm)
            return

        log4(evm)
        assert evm == cairo_result

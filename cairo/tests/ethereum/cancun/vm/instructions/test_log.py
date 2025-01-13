import pytest
from ethereum_types.numeric import U256
from hypothesis import given

from ethereum.cancun.vm.exceptions import ExceptionalHalt
from ethereum.cancun.vm.instructions.log import log0, log1, log2, log3, log4
from ethereum.cancun.vm.stack import push
from tests.utils.args_gen import Evm
from tests.utils.evm_builder import EvmBuilder
from tests.utils.strategies import memory_lite_access_size, memory_lite_start_position

tests_log_strategy = EvmBuilder().with_stack().with_gas_left().with_memory().build()


class TestLog:
    @given(
        evm=tests_log_strategy,
        start_index=memory_lite_start_position,
        size=memory_lite_access_size,
    )
    def test_log0(self, cairo_run, evm: Evm, start_index: U256, size: U256):
        push(evm.stack, start_index)
        push(evm.stack, size)
        try:
            cairo_result = cairo_run("log0", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                log0(evm)
            return

        log0(evm)
        assert evm == cairo_result

    @given(
        evm=tests_log_strategy,
        start_index=memory_lite_start_position,
        size=memory_lite_access_size,
        topic1=...,
    )
    def test_log1(
        self, cairo_run, evm: Evm, start_index: U256, size: U256, topic1: U256
    ):
        push(evm.stack, start_index)
        push(evm.stack, size)
        push(evm.stack, topic1)
        try:
            cairo_result = cairo_run("log1", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                log1(evm)
            return

        log1(evm)
        assert evm == cairo_result

    @given(
        evm=tests_log_strategy,
        start_index=memory_lite_start_position,
        size=memory_lite_access_size,
        topic1=...,
        topic2=...,
    )
    def test_log2(
        self,
        cairo_run,
        evm: Evm,
        start_index: U256,
        size: U256,
        topic1: U256,
        topic2: U256,
    ):
        push(evm.stack, start_index)
        push(evm.stack, size)
        push(evm.stack, topic1)
        push(evm.stack, topic2)
        try:
            cairo_result = cairo_run("log2", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                log2(evm)
            return

        log2(evm)
        assert evm == cairo_result

    @given(
        evm=tests_log_strategy,
        start_index=memory_lite_start_position,
        size=memory_lite_access_size,
        topic1=...,
        topic2=...,
        topic3=...,
    )
    def test_log3(
        self,
        cairo_run,
        evm: Evm,
        start_index: U256,
        size: U256,
        topic1: U256,
        topic2: U256,
        topic3: U256,
    ):
        push(evm.stack, start_index)
        push(evm.stack, size)
        push(evm.stack, topic1)
        push(evm.stack, topic2)
        push(evm.stack, topic3)
        try:
            cairo_result = cairo_run("log3", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                log3(evm)
            return

        log3(evm)
        assert evm == cairo_result

    @given(
        evm=tests_log_strategy,
        start_index=memory_lite_start_position,
        size=memory_lite_access_size,
        topic1=...,
        topic2=...,
        topic3=...,
        topic4=...,
    )
    def test_log4(
        self,
        cairo_run,
        evm: Evm,
        start_index: U256,
        size: U256,
        topic1: U256,
        topic2: U256,
        topic3: U256,
        topic4: U256,
    ):
        push(evm.stack, start_index)
        push(evm.stack, size)
        push(evm.stack, topic1)
        push(evm.stack, topic2)
        push(evm.stack, topic3)
        push(evm.stack, topic4)
        try:
            cairo_result = cairo_run("log4", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                log4(evm)
            return

        log4(evm)
        assert evm == cairo_result

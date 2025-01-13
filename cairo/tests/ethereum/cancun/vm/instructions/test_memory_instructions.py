import pytest
from ethereum_types.numeric import U256
from hypothesis import given

from ethereum.cancun.vm.exceptions import ExceptionalHalt
from ethereum.cancun.vm.instructions.memory import mcopy, mload, msize, mstore, mstore8
from ethereum.cancun.vm.stack import push
from tests.utils.args_gen import Evm
from tests.utils.evm_builder import EvmBuilder
from tests.utils.strategies import (
    memory_lite_access_size,
    memory_lite_destination,
    memory_lite_start_position,
)

tests_memory_strategy = EvmBuilder().with_stack().with_gas_left().with_memory().build()


class TestMemory:
    @given(
        evm=tests_memory_strategy,
        start_position=memory_lite_start_position,
        size=memory_lite_access_size,
        push_on_stack=...,
    )
    def test_mstore(
        self, cairo_run, evm: Evm, start_position: U256, size: U256, push_on_stack: bool
    ):
        if push_on_stack:  # to ensure valid cases are generated
            push(evm.stack, start_position)
            push(evm.stack, size)
        try:
            cairo_result = cairo_run("mstore", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                mstore(evm)
            return

        mstore(evm)
        assert evm == cairo_result

    @given(
        evm=tests_memory_strategy,
        start_position=memory_lite_start_position,
        size=memory_lite_access_size,
        push_on_stack=...,
    )
    def test_mstore8(
        self, cairo_run, evm: Evm, start_position: U256, size: U256, push_on_stack: bool
    ):
        if push_on_stack:  # to ensure valid cases are generated
            push(evm.stack, start_position)
            push(evm.stack, size)

        try:
            cairo_result = cairo_run("mstore8", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                mstore8(evm)
            return

        mstore8(evm)
        assert evm == cairo_result

    @given(
        evm=tests_memory_strategy,
        start_position=memory_lite_start_position,
        push_on_stack=...,
    )
    def test_mload(
        self, cairo_run, evm: Evm, start_position: U256, push_on_stack: bool
    ):
        if push_on_stack:  # to ensure valid cases are generated
            push(evm.stack, start_position)

        try:
            cairo_result = cairo_run("mload", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                mload(evm)
            return

        mload(evm)
        assert evm == cairo_result

    @given(evm=tests_memory_strategy)
    def test_msize(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("msize", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                msize(evm)
            return

        msize(evm)
        assert evm == cairo_result

    @given(
        evm=tests_memory_strategy,
        start_position=memory_lite_start_position,
        size=memory_lite_access_size,
        destination=memory_lite_destination,
        push_on_stack=...,
    )
    def test_mcopy(
        self,
        cairo_run,
        evm: Evm,
        start_position: U256,
        size: U256,
        destination: U256,
        push_on_stack: bool,
    ):
        if push_on_stack:  # to ensure valid cases are generated
            push(evm.stack, size)
            push(evm.stack, start_position)
            push(evm.stack, destination)
        try:
            cairo_result = cairo_run("mcopy", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                mcopy(evm)
            return

        mcopy(evm)
        assert evm == cairo_result

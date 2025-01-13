import pytest
from hypothesis import given

import ethereum.cancun.vm.instructions.stack as stack
from ethereum.cancun.vm.exceptions import ExceptionalHalt
from tests.utils.args_gen import Evm
from tests.utils.evm_builder import EvmBuilder

pytestmark = pytest.mark.python_vm


class TestPushN:
    @pytest.mark.parametrize("num_bytes", range(33))
    @given(evm=EvmBuilder().with_stack().with_gas_left().with_code().build())
    def test_push_n(self, cairo_run, evm: Evm, num_bytes: int):
        func_name = f"push{num_bytes}"
        push_i = getattr(stack, func_name)
        try:
            cairo_result = cairo_run(func_name, evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                push_i(evm)
            return

        push_i(evm)
        assert evm == cairo_result


class TestSwapN:
    @pytest.mark.parametrize("item_number", range(1, 17))
    @given(evm=EvmBuilder().with_stack().with_gas_left().build())
    def test_swap_n(self, cairo_run, evm: Evm, item_number: int):
        func_name = f"swap{item_number}"
        swap_i = getattr(stack, func_name)
        try:
            cairo_result = cairo_run(func_name, evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                swap_i(evm)
            return

        swap_i(evm)
        assert evm == cairo_result


class TestDupN:
    @pytest.mark.parametrize("item_number", range(1, 17))
    @given(evm=EvmBuilder().with_stack().with_gas_left().build())
    def test_dup_n(self, cairo_run, evm: Evm, item_number: int):
        func_name = f"dup{item_number}"
        dup_i = getattr(stack, func_name)
        try:
            cairo_result = cairo_run(func_name, evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                dup_i(evm)
            return
        dup_i(evm)
        assert evm == cairo_result

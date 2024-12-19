import pytest
from ethereum_types.numeric import U256
from hypothesis import given

from ethereum.cancun.vm.exceptions import StackOverflowError, StackUnderflowError
from ethereum.cancun.vm.stack import pop, push
from tests.utils.args_gen import Stack


class TestStack:
    @given(stack=...)
    def test_pop(self, cairo_run, stack: Stack):
        if len(stack) == 0:
            with pytest.raises(StackUnderflowError):
                cairo_run("pop", stack)
            with pytest.raises(StackUnderflowError):
                pop(stack)
            return

        (new_stack_cairo, popped_value_cairo) = cairo_run("pop", stack)
        popped_value_py = pop(stack)
        assert new_stack_cairo == stack
        assert popped_value_cairo == popped_value_py

    @given(stack=..., value=...)
    def test_push(self, cairo_run, stack: Stack, value: U256):
        if len(stack) >= 1024:
            with pytest.raises(StackOverflowError):
                cairo_run("push", stack, value)
            with pytest.raises(StackOverflowError):
                push(stack, value)

        new_stack_cairo = cairo_run("push", stack, value)
        push(stack, value)
        assert new_stack_cairo == stack

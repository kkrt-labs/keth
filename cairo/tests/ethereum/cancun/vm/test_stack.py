from typing import List

import pytest
from ethereum_types.numeric import U256
from hypothesis import assume, given

from ethereum.cancun.vm.exceptions import StackOverflowError, StackUnderflowError
from ethereum.cancun.vm.stack import pop, push


class TestStack:
    def test_pop_underflow(self, cairo_run):
        stack = []
        with pytest.raises(StackUnderflowError):
            cairo_run("pop", stack)
        with pytest.raises(StackUnderflowError):
            pop(stack)

    @given(stack=...)
    def test_pop_success(self, cairo_run, stack: List[U256]):
        assume(len(stack) > 0)

        (new_stack_cairo, popped_value_cairo) = cairo_run("pop", stack)
        popped_value_py = pop(stack)
        assert new_stack_cairo == stack
        assert popped_value_cairo == popped_value_py

    @given(value=...)
    def test_push_overflow(self, cairo_run, value: U256):
        stack = [U256(0)] * 1024
        with pytest.raises(StackOverflowError):
            cairo_run("push", stack, value)
        with pytest.raises(StackOverflowError):
            push(stack, value)

    @given(stack=..., value=...)
    def test_push_success(self, cairo_run, stack: List[U256], value: U256):
        new_stack_cairo = cairo_run("push", stack, value)
        push(stack, value)
        assert new_stack_cairo == stack

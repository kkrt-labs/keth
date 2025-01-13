import pytest
from hypothesis import given

from ethereum.cancun.vm.exceptions import ExceptionalHalt
from ethereum.cancun.vm.instructions.comparison import (
    equal,
    greater_than,
    is_zero,
    less_than,
    signed_greater_than,
    signed_less_than,
)
from tests.utils.args_gen import Evm
from tests.utils.evm_builder import EvmBuilder

comparison_tests_strategy = EvmBuilder().with_stack().with_gas_left().build()


class TestComparison:
    @given(evm=comparison_tests_strategy)
    def test_less_than(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("less_than", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                less_than(evm)
            return

        less_than(evm)
        assert evm == cairo_result

    @given(evm=comparison_tests_strategy)
    def test_greater_than(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("greater_than", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                greater_than(evm)
            return

        greater_than(evm)
        assert evm == cairo_result

    @given(evm=comparison_tests_strategy)
    def test_signed_less_than(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("signed_less_than", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                signed_less_than(evm)
            return

        signed_less_than(evm)
        assert evm == cairo_result

    @given(evm=comparison_tests_strategy)
    def test_signed_greater_than(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("signed_greater_than", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                signed_greater_than(evm)
            return

        signed_greater_than(evm)
        assert evm == cairo_result

    @given(evm=comparison_tests_strategy)
    def test_equal(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("equal", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                equal(evm)
            return

        equal(evm)
        assert evm == cairo_result

    @given(evm=comparison_tests_strategy)
    def test_is_zero(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("is_zero", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                is_zero(evm)
            return

        is_zero(evm)
        assert evm == cairo_result

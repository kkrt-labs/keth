import pytest
from hypothesis import given

from ethereum.cancun.vm.exceptions import ExceptionalHalt
from ethereum.cancun.vm.instructions.bitwise import (
    bitwise_and,
    bitwise_not,
    bitwise_or,
    bitwise_sar,
    bitwise_shl,
    bitwise_shr,
    bitwise_xor,
    get_byte,
)
from tests.utils.args_gen import Evm
from tests.utils.evm_builder import EvmBuilder

bitwise_tests_strategy = EvmBuilder().with_stack().with_gas_left().build()


class TestBitwise:
    @given(evm=bitwise_tests_strategy)
    def test_and(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("bitwise_and", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                bitwise_and(evm)
            return

        bitwise_and(evm)
        assert evm == cairo_result

    @given(evm=bitwise_tests_strategy)
    def test_or(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("bitwise_or", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                bitwise_or(evm)
            return

        bitwise_or(evm)
        assert evm == cairo_result

    @given(evm=bitwise_tests_strategy)
    def test_xor(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("bitwise_xor", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                bitwise_xor(evm)
            return

        bitwise_xor(evm)
        assert evm == cairo_result

    @given(evm=bitwise_tests_strategy)
    def test_not(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("bitwise_not", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                bitwise_not(evm)
            return

        bitwise_not(evm)
        assert evm == cairo_result

    @given(evm=bitwise_tests_strategy)
    def test_get_byte(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("get_byte", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                get_byte(evm)
            return

        get_byte(evm)
        assert evm == cairo_result

    @given(evm=bitwise_tests_strategy)
    def test_shl(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("bitwise_shl", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                bitwise_shl(evm)
            return

        bitwise_shl(evm)
        assert evm == cairo_result

    @given(evm=bitwise_tests_strategy)
    def test_shr(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("bitwise_shr", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                bitwise_shr(evm)
            return

        bitwise_shr(evm)
        assert evm == cairo_result

    @given(evm=bitwise_tests_strategy)
    def test_sar(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("bitwise_sar", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                bitwise_sar(evm)
            return

        bitwise_sar(evm)
        assert evm == cairo_result

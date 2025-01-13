import pytest
from hypothesis import given

from ethereum.cancun.vm.instructions.arithmetic import (
    add,
    addmod,
    div,
    exp,
    mod,
    mul,
    mulmod,
    sdiv,
    signextend,
    smod,
    sub,
)
from tests.utils.args_gen import Evm
from tests.utils.evm_builder import EvmBuilder

arithmetic_tests_strategy = EvmBuilder().with_stack().with_gas_left().build()


class TestArithmetic:
    @given(evm=arithmetic_tests_strategy)
    def test_add(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("add", evm)
        except Exception as cairo_error:
            with pytest.raises(type(cairo_error)):
                add(evm)
            return

        add(evm)
        assert evm == cairo_result

    @given(evm=arithmetic_tests_strategy)
    def test_sub(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("sub", evm)
        except Exception as cairo_error:
            with pytest.raises(type(cairo_error)):
                sub(evm)
            return

        sub(evm)
        assert evm == cairo_result

    @given(evm=arithmetic_tests_strategy)
    def test_mul(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("mul", evm)
        except Exception as cairo_error:
            with pytest.raises(type(cairo_error)):
                mul(evm)
            return

        mul(evm)
        assert evm == cairo_result

    @given(evm=arithmetic_tests_strategy)
    def test_div(self, cairo_run, evm: Evm):
        """Test the DIV operation"""
        try:
            cairo_result = cairo_run("div", evm)
        except Exception as cairo_error:
            with pytest.raises(type(cairo_error)):
                div(evm)
            return

        div(evm)
        assert evm == cairo_result

    @given(evm=arithmetic_tests_strategy)
    def test_sdiv(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("sdiv", evm)
        except Exception as cairo_error:
            with pytest.raises(type(cairo_error)):
                sdiv(evm)
            return

        sdiv(evm)
        assert evm == cairo_result

    @given(evm=arithmetic_tests_strategy)
    def test_mod(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("mod", evm)
        except Exception as cairo_error:
            with pytest.raises(type(cairo_error)):
                mod(evm)
            return

        mod(evm)
        assert evm == cairo_result

    @given(evm=arithmetic_tests_strategy)
    def test_smod(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("smod", evm)
        except Exception as cairo_error:
            with pytest.raises(type(cairo_error)):
                smod(evm)
            return

        smod(evm)
        assert evm == cairo_result

    @given(evm=arithmetic_tests_strategy)
    def test_addmod(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("addmod", evm)
        except Exception as cairo_error:
            with pytest.raises(type(cairo_error)):
                addmod(evm)
            return

        addmod(evm)
        assert evm == cairo_result

    @given(evm=arithmetic_tests_strategy)
    def test_mulmod(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("mulmod", evm)
        except Exception as cairo_error:
            with pytest.raises(type(cairo_error)):
                mulmod(evm)
            return

        mulmod(evm)
        assert evm == cairo_result

    @given(evm=arithmetic_tests_strategy)
    def test_exp(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("exp", evm)
        except Exception as cairo_error:
            with pytest.raises(type(cairo_error)):
                exp(evm)
            return

        exp(evm)
        assert evm == cairo_result

    @given(evm=arithmetic_tests_strategy)
    def test_signextend(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("signextend", evm)
        except Exception as cairo_error:
            with pytest.raises(type(cairo_error)):
                signextend(evm)
            return

        signextend(evm)
        assert evm == cairo_result

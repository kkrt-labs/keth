import pytest
from hypothesis import given

from ethereum.cancun.vm.exceptions import ExceptionalHalt
from ethereum.cancun.vm.instructions.memory import mcopy, mload, msize, mstore, mstore8
from tests.utils.args_gen import Evm
from tests.utils.strategies import evm_lite


class TestMemory:
    @given(evm=evm_lite)
    def test_mstore(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("mstore", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                mstore(evm)
            return

        mstore(evm)
        assert evm == cairo_result

    @given(evm=evm_lite)
    def test_mstore8(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("mstore8", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                mstore8(evm)
            return

        mstore8(evm)
        assert evm == cairo_result

    @given(evm=evm_lite)
    def test_mload(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("mload", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                mload(evm)
            return

        mload(evm)
        assert evm == cairo_result

    @given(evm=evm_lite)
    def test_msize(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("msize", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                msize(evm)
            return

        msize(evm)
        assert evm == cairo_result

    @given(evm=evm_lite)
    def test_mcopy(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("mcopy", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                mcopy(evm)
            return

        mcopy(evm)
        assert evm == cairo_result

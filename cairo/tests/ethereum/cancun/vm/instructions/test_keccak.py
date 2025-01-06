from datetime import timedelta

import pytest
from hypothesis import given, settings

from ethereum.cancun.vm.exceptions import ExceptionalHalt
from ethereum.cancun.vm.instructions.keccak import keccak
from tests.utils.args_gen import Evm
from tests.utils.strategies import evm_lite


class TestKeccak:
    @settings(deadline=timedelta(milliseconds=20000))
    @given(evm=evm_lite)
    def test_keccak(self, cairo_run, evm: Evm):
        """
        Test the keccak instruction by comparing Cairo and Python implementations
        """
        try:
            cairo_result = cairo_run("keccak", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                keccak(evm)
            return

        keccak(evm)
        assert evm == cairo_result

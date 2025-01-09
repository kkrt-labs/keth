import pytest
from ethereum_types.numeric import Uint
from hypothesis import given
from hypothesis import strategies as st

from ethereum.cancun.vm.exceptions import ExceptionalHalt
from ethereum.cancun.vm.instructions.stack import push_n
from tests.utils.args_gen import Evm
from tests.utils.strategies import evm_lite


class TestPushN:
    @given(evm=evm_lite, num_bytes=st.integers(min_value=0, max_value=32).map(Uint))
    def test_push_n(self, cairo_run, evm: Evm, num_bytes: Uint):
        """
        Test the push_n instruction by comparing Cairo and Python implementations
        """
        try:
            cairo_result = cairo_run("push_n", evm, num_bytes)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                push_n(evm, num_bytes)
            return

        # Run Python implementation
        push_n(evm, num_bytes)
        assert evm == cairo_result

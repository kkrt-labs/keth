import pytest
from hypothesis import given

from ethereum.cancun.vm.instructions.storage import sload
from tests.utils.args_gen import Evm
from tests.utils.evm_builder import EvmBuilder

pytestmark = pytest.mark.python_vm


class TestStorage:
    @given(evm=EvmBuilder().with_stack().with_env().with_gas_left().build())
    def test_sload(self, cairo_run, evm: Evm):
        try:
            cairo_evm = cairo_run("sload", evm)
        except Exception as cairo_error:
            with pytest.raises(type(cairo_error)):
                sload(evm)
            return

        sload(evm)
        assert evm == cairo_evm

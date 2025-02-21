from ethereum.cancun.vm import Evm
from ethereum.cancun.vm.precompiled_contracts.ecrecover import ecrecover
from ethereum.exceptions import EthereumException
from hypothesis import given

from cairo_addons.testing.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder
from tests.utils.message_builder import MessageBuilder


@given(
    evm=EvmBuilder()
    .with_gas_left()
    .with_message(MessageBuilder().with_data().build())
    .build()
)
def test_ecrecover(cairo_run, evm: Evm):
    try:
        cairo_evm = cairo_run("ecrecover", evm)
    except EthereumException as e:
        with strict_raises(type(e)):
            ecrecover(evm)
        return

    ecrecover(evm)
    assert cairo_evm == evm

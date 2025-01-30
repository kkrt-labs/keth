from hypothesis import given

from ethereum.cancun.vm.precompiled_contracts.identity import identity
from ethereum.exceptions import EthereumException
from tests.utils.args_gen import Evm
from tests.utils.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder
from tests.utils.message_builder import MessageBuilder


@given(
    evm=EvmBuilder()
    .with_gas_left()
    .with_message(MessageBuilder().with_data().build())
    .build()
)
def test_identity(cairo_run, evm: Evm):
    try:
        cairo_evm = cairo_run("identity", evm)
    except EthereumException as e:
        with strict_raises(type(e)):
            identity(evm)
        return

    identity(evm)
    assert cairo_evm == evm

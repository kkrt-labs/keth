from ethereum.cancun.vm import Evm
from ethereum.cancun.vm.precompiled_contracts.sha256 import sha256
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
def test_sha256(cairo_run, evm: Evm):
    try:
        cairo_evm = cairo_run("sha256", evm)
    except EthereumException as e:
        with strict_raises(type(e)):
            sha256(evm)
        return

    sha256(evm)
    assert cairo_evm == evm

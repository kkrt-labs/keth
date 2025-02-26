import hashlib

from ethereum.cancun.vm import Evm
from ethereum.cancun.vm.precompiled_contracts.ripemd160 import ripemd160
from ethereum.utils.byte import left_pad_zero_bytes
from ethereum_types.numeric import Uint
from hypothesis import given
from hypothesis import strategies as st
from hypothesis.strategies import composite

from cairo_addons.testing.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder
from tests.utils.message_builder import MessageBuilder


@composite
def evm_test_strategy(draw):
    input_bytes = draw(st.binary(min_size=0, max_size=1024))
    message = MessageBuilder().with_data(st.just(input_bytes)).build()
    return draw(EvmBuilder().with_gas_left().with_message(message).build())


class TestRIPEMD160:
    @given(evm=evm_test_strategy())
    def test_ripemd160(self, cairo_run, evm: Evm):
        input_data = evm.message.data

        expected_hash = hashlib.new("ripemd160", input_data).digest()
        expected_output = left_pad_zero_bytes(expected_hash, 32)

        try:
            cairo_result = cairo_run("ripemd160", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                ripemd160(evm)
            return

        ripemd160(evm)

        assert evm == cairo_result
        assert cairo_result.output == expected_output

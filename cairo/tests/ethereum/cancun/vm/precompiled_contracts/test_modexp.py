import hypothesis.strategies as st
from ethereum.cancun.vm import Evm
from ethereum.cancun.vm.precompiled_contracts.modexp import modexp
from ethereum_types.bytes import Bytes
from hypothesis import given

from cairo_addons.testing.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder
from tests.utils.message_builder import MessageBuilder


class TestModexp:
    @given(
        base=st.binary(max_size=2048),
        exp=st.binary(max_size=2048),
        mod=st.binary(max_size=2048),
        evm=EvmBuilder()
        .with_gas_left()
        .with_message(MessageBuilder().with_data().build())
        .build(),
    )
    def test_modexp(self, cairo_run, evm: Evm, base: Bytes, exp: Bytes, mod: Bytes):
        base_len = len(base).to_bytes(32, "big")
        exp_len = len(exp).to_bytes(32, "big")
        mod_len = len(mod).to_bytes(32, "big")

        data = base_len + exp_len + mod_len + base + exp + mod
        evm.message.data = Bytes(data)

        try:
            evm_cairo = cairo_run("modexp", evm=evm)
        except Exception as e:
            with strict_raises(type(e)):
                modexp(evm)
            return

        modexp(evm)
        assert evm == evm_cairo

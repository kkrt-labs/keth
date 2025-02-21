from ethereum.cancun.vm import Evm
from ethereum.cancun.vm.precompiled_contracts.alt_bn128 import (
    alt_bn128_add,
    alt_bn128_mul,
    alt_bn128_pairing_check,
)
from ethereum_types.bytes import Bytes
from hypothesis import given
from hypothesis import strategies as st

from cairo_addons.testing.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder


@st.composite
def data_strategy(draw):
    is_mul_192 = draw(st.booleans())
    base = draw(st.integers(min_value=0, max_value=192))
    if is_mul_192:
        return draw(st.binary(min_size=0, max_size=base * 192))
    else:
        return draw(st.binary(min_size=0, max_size=base * 193))


class TestAltbn128:
    @given(
        evm=EvmBuilder().with_gas_left().build(),
        data=data_strategy(),
    )
    def test_alt_bn128_pairing_check(self, cairo_run, evm: Evm, data: Bytes):
        evm.message.data = data

        try:
            evm_cairo = cairo_run("alt_bn128_pairing_check", evm=evm)
        except Exception as e:
            with strict_raises(type(e)):
                alt_bn128_pairing_check(evm)
            return

        alt_bn128_pairing_check(evm)
        assert evm == evm_cairo

    @given(
        evm=EvmBuilder().with_gas_left().build(),
        data=data_strategy(),
    )
    def test_alt_bn128_add(self, cairo_run, evm: Evm, data: Bytes):
        evm.message.data = data

        try:
            evm_cairo = cairo_run("alt_bn128_add", evm=evm)
        except Exception as e:
            with strict_raises(type(e)):
                alt_bn128_add(evm)
            return

        alt_bn128_add(evm)
        assert evm == evm_cairo

    @given(
        evm=EvmBuilder().with_gas_left().build(),
        data=data_strategy(),
    )
    def test_alt_bn128_mul(self, cairo_run, evm: Evm, data: Bytes):
        evm.message.data = data

        try:
            evm_cairo = cairo_run("alt_bn128_mul", evm=evm)
        except Exception as e:
            with strict_raises(type(e)):
                alt_bn128_mul(evm)
            return

        alt_bn128_mul(evm)
        assert evm == evm_cairo

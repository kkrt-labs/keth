from ethereum.prague.vm import Evm
from ethereum.prague.vm.precompiled_contracts.bls12_381.bls12_381_g1 import (
    G1_to_bytes,
    bls12_g1_add,
)
from ethereum_types.bytes import Bytes
from hypothesis import given
from hypothesis import strategies as st
from py_ecc.optimized_bls12_381.optimized_curve import Z1

from cairo_addons.testing.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder
from tests.utils.strategies import blsp_strategy


@st.composite
def bls12_g1_add_data(draw):
    p1 = draw(blsp_strategy)
    p2 = draw(blsp_strategy)
    assert p1[2] == 0 if p1 == Z1 else p1[2] == 1
    assert p2[2] == 0 if p2 == Z1 else p2[2] == 1

    return G1_to_bytes((p1[0], p1[1])) + G1_to_bytes((p2[0], p2[1]))


@given(
    evm=EvmBuilder().with_gas_left().with_message().build(), data=bls12_g1_add_data()
)
def test_bls12_g1_add(cairo_run, evm: Evm, data: Bytes):
    evm.message.data = data
    try:
        evm_cairo = cairo_run("bls12_g1_add", evm, data)
    except Exception as e:
        with strict_raises(type(e)):
            bls12_g1_add(evm)
        return
    bls12_g1_add(evm)
    assert evm_cairo == evm

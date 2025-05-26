from ethereum.prague.vm import Evm
from ethereum.prague.vm.precompiled_contracts.bls12_381.bls12_381_g1 import G1_to_bytes
from ethereum.prague.vm.precompiled_contracts.bls12_381.bls12_381_g2 import G2_to_bytes
from ethereum.prague.vm.precompiled_contracts.bls12_381.bls12_381_pairing import (
    bls12_pairing,
)
from ethereum_types.bytes import Bytes
from hypothesis import given
from hypothesis import strategies as st
from py_ecc.fields import optimized_bls12_381_FQ2 as FQ2
from py_ecc.optimized_bls12_381.optimized_curve import Z1, Z2

from cairo_addons.testing.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder
from tests.utils.strategies import blsp2_strategy, blsp_strategy


@st.composite
def bls12_381_pairing_data(draw):
    num_points = draw(st.integers(min_value=1, max_value=10))
    g1_points = draw(st.lists(blsp_strategy, min_size=num_points, max_size=num_points))
    g2_points = draw(st.lists(blsp2_strategy, min_size=num_points, max_size=num_points))
    result = Bytes(b"")
    for i in range(num_points):
        assert g1_points[i][2] == 0 if g1_points[i] == Z1 else g1_points[i][2] == 1
        assert (
            g2_points[i][2] == FQ2.zero()
            if g2_points[i] == Z2
            else g2_points[i][2] == FQ2.one()
        )
        result += G1_to_bytes(g1_points[i][:2]) + G2_to_bytes(g2_points[i][:2])
    return result


@given(
    evm=EvmBuilder().with_gas_left().with_message().build(),
    data=bls12_381_pairing_data(),
)
def test_bls12_381_pairing(cairo_run, evm: Evm, data: Bytes):
    evm.message.data = data
    try:
        evm_cairo = cairo_run("bls12_pairing", evm, data)
    except Exception as e:
        with strict_raises(type(e)):
            bls12_pairing(evm)
        return
    bls12_pairing(evm)
    assert evm_cairo == evm

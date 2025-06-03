from ethereum.prague.vm import Evm
from ethereum.prague.vm.precompiled_contracts.bls12_381.bls12_381_g2 import (
    G2_to_bytes,
    bls12_g2_add,
    bls12_g2_msm,
    bls12_map_fp2_to_g2,
)
from ethereum_types.bytes import Bytes
from hypothesis import given
from hypothesis import strategies as st
from py_ecc.fields import optimized_bls12_381_FQ2 as FQ2
from py_ecc.optimized_bls12_381.optimized_curve import Z2

from cairo_addons.testing.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder
from tests.utils.strategies import blsf2_strategy, blsp2_strategy


@st.composite
def bls12_g2_add_data(draw):
    p1 = draw(blsp2_strategy)
    p2 = draw(blsp2_strategy)
    assert p1[2] == FQ2.zero() if p1 == Z2 else p1[2] == FQ2.one()
    assert p2[2] == FQ2.zero() if p2 == Z2 else p2[2] == FQ2.one()

    return G2_to_bytes((p1[0], p1[1])) + G2_to_bytes((p2[0], p2[1]))


@st.composite
def bls12_g2_msm_data(draw):
    points = draw(st.lists(blsp2_strategy, min_size=1, max_size=128))
    result = b""
    for p in points:
        assert p[2] == FQ2.zero() if p == Z2 else p[2] == FQ2.one()
        result += G2_to_bytes((p[0], p[1]))
    return result


@st.composite
def bls12_g2_map_fp2_to_g2_data(draw):
    fp2_1 = draw(blsf2_strategy)
    fp2_2 = draw(blsf2_strategy)
    return G2_to_bytes((fp2_1, fp2_2))


@given(
    evm=EvmBuilder().with_gas_left().with_message().build(), data=bls12_g2_add_data()
)
def test_bls12_g2_add(cairo_run, evm: Evm, data: Bytes):
    evm.message.data = data
    try:
        evm_cairo = cairo_run("bls12_g2_add", evm, data)
    except Exception as e:
        with strict_raises(type(e)):
            bls12_g2_add(evm)
        return
    bls12_g2_add(evm)
    assert evm_cairo == evm


@given(
    evm=EvmBuilder().with_gas_left().with_message().build(), data=bls12_g2_msm_data()
)
def test_bls12_g2_msm(cairo_run, evm: Evm, data: Bytes):
    evm.message.data = data
    try:
        evm_cairo = cairo_run("bls12_g2_msm", evm, data)
    except Exception as e:
        with strict_raises(type(e)):
            bls12_g2_msm(evm)
        return
    bls12_g2_msm(evm)
    assert evm_cairo == evm


@given(
    evm=EvmBuilder().with_gas_left().with_message().build(),
    data=bls12_g2_map_fp2_to_g2_data(),
)
def test_bls12_g2_map_fp_to_g2(cairo_run, evm: Evm, data: Bytes):
    evm.message.data = data
    try:
        evm_cairo = cairo_run("bls12_map_fp2_to_g2", evm, data)
    except Exception as e:
        with strict_raises(type(e)):
            bls12_map_fp2_to_g2(evm)
        return
    bls12_map_fp2_to_g2(evm)
    assert evm_cairo == evm

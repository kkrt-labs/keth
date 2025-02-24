from ethereum.cancun.vm import Evm
from ethereum.cancun.vm.precompiled_contracts.ecrecover import ecrecover
from ethereum.crypto.elliptic_curve import SECP256K1N
from ethereum.crypto.hash import Hash32
from ethereum.exceptions import EthereumException
from ethereum_types.numeric import U256
from hypothesis import given
from hypothesis import strategies as st

from cairo_addons.testing.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder
from tests.utils.message_builder import MessageBuilder
from tests.utils.strategies import private_key


@st.composite
def ecrecover_data(draw):
    pkey = draw(private_key)
    message = draw(st.from_type(Hash32))
    signature = pkey.sign_msg_hash(message)
    r = U256(signature.r)
    s = U256(signature.s)
    v = U256(signature.v + 27)

    # test the error cases by changing r, s, v with 10% probability
    prob_r = draw(st.integers(min_value=0, max_value=9))
    prob_s = draw(st.integers(min_value=0, max_value=9))
    prob_v = draw(st.integers(min_value=0, max_value=9))

    if prob_r == 0:
        r = U256(SECP256K1N + U256(1))
    if prob_s == 0:
        s = U256(SECP256K1N + U256(1))
    if prob_v == 0:
        v = U256(1)

    data = message + v.to_be_bytes32() + r.to_be_bytes32() + s.to_be_bytes32()

    evm = draw(
        EvmBuilder()
        .with_gas_left()
        .with_message(MessageBuilder().with_data(st.just(data)).build())
        .build()
    )
    return evm


@given(evm=ecrecover_data())
def test_ecrecover(cairo_run, evm: Evm):
    try:
        cairo_evm = cairo_run("ecrecover", evm)
    except EthereumException as e:
        with strict_raises(type(e)):
            ecrecover(evm)
        return

    ecrecover(evm)
    assert cairo_evm == evm

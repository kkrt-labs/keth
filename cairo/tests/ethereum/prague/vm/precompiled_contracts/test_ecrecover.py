from ethereum.crypto.elliptic_curve import SECP256K1N
from ethereum.crypto.hash import Hash32
from ethereum.exceptions import EthereumException
from ethereum.prague.vm import Evm
from ethereum.prague.vm.precompiled_contracts.ecrecover import ecrecover
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

    test_case = draw(
        st.sampled_from(
            [
                "valid_signature",  # Normal valid case
                "invalid_r_overflow",  # r >= SECP256K1N
                "invalid_r_zero",  # r = 0
                "invalid_s_overflow",  # s >= SECP256K1N
                "invalid_s_zero",  # s = 0
                "invalid_v",  # v not 27 or 28
            ]
        )
    )

    if test_case == "invalid_r_overflow":
        r = U256(SECP256K1N + U256(1))
    elif test_case == "invalid_r_zero":
        r = U256(0)
    elif test_case == "invalid_s_overflow":
        s = U256(SECP256K1N + U256(1))
    elif test_case == "invalid_s_zero":
        s = U256(0)
    elif test_case == "invalid_v":
        v = U256(
            draw(
                st.integers(min_value=1, max_value=26).filter(
                    lambda x: x not in [27, 28]
                )
            )
        )

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

from ethereum.prague.vm import Evm
from ethereum.prague.vm.precompiled_contracts.blake2f import blake2f
from hypothesis import given
from hypothesis import strategies as st
from hypothesis.strategies import composite

from cairo_addons.testing.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder
from tests.utils.message_builder import MessageBuilder


@composite
def evm_test_strategy(draw):
    # Generate Blake2F parameters
    rounds = draw(st.integers(min_value=0, max_value=4))
    h = [draw(st.integers(min_value=0, max_value=2**64 - 1)) for _ in range(8)]
    m = [draw(st.integers(min_value=0, max_value=2**64 - 1)) for _ in range(16)]
    t_0 = draw(st.integers(min_value=0, max_value=2**64 - 1))
    t_1 = draw(st.integers(min_value=0, max_value=2**64 - 1))
    f = draw(st.integers(min_value=0, max_value=1))

    # Create input bytes
    rounds_bytes = rounds.to_bytes(4, byteorder="big")
    h_bytes = b"".join(x.to_bytes(8, byteorder="little") for x in h)
    m_bytes = b"".join(x.to_bytes(8, byteorder="little") for x in m)
    t_0_bytes = t_0.to_bytes(8, byteorder="little")
    t_1_bytes = t_1.to_bytes(8, byteorder="little")
    f_bytes = bytes([f])

    input_bytes = rounds_bytes + h_bytes + m_bytes + t_0_bytes + t_1_bytes + f_bytes

    # Create message with data
    # Send valid input bytes 80% of the time
    if draw(st.floats(min_value=0, max_value=1)) < 0.8:
        message = MessageBuilder().with_data(st.just(input_bytes)).build()
    else:
        input_bytes = draw(
            st.one_of(
                st.binary(min_size=1, max_size=1024),
                st.just(
                    input_bytes[:-1]
                    + bytes([draw(st.integers(min_value=2, max_value=255))])
                ),
            )
        )
        message = MessageBuilder().with_data(st.just(input_bytes)).build()

    # Build and return EVM instance
    return draw(EvmBuilder().with_gas_left().with_message(message).build())


class TestBlake2F:
    @given(evm=evm_test_strategy())
    def test_blake2f(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("blake2f", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                blake2f(evm)
            return

        blake2f(evm)
        assert evm == cairo_result

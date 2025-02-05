from ethereum.cancun.fork_types import Address
from ethereum.cancun.vm import Evm
from ethereum.cancun.vm.instructions.system import return_, revert, selfdestruct
from ethereum.cancun.vm.stack import push
from ethereum_types.numeric import U256
from hypothesis import given
from hypothesis import strategies as st
from hypothesis.strategies import composite

from tests.utils.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder
from tests.utils.strategies import memory_lite_access_size, memory_lite_start_position


@composite
def revert_return_strategy(draw):
    """Generate test cases for system instructions (revert/return).

    This strategy generates an EVM instance and the required parameters.
    - 8/10 chance: pushes all parameters onto the stack to test normal operation
    - 2/10 chance: use stack already populated with values, mostly to test error cases
    """
    evm = draw(EvmBuilder().with_stack().with_gas_left().with_memory().build())
    memory_start = draw(memory_lite_start_position)
    size = draw(memory_lite_access_size)

    # 80% chance to push valid values onto stack
    should_push = draw(st.integers(0, 99)) < 80
    if should_push:
        push(evm.stack, size)
        push(evm.stack, memory_start)

    return evm


@composite
def beneficiary_from_state(draw):
    """Generate test cases for selfdestruct instruction.

    This strategy generates an EVM instance with a beneficiary address on the stack:
    - 80% chance: address from state (existing accounts)
    - 20% chance: random address
    - Always pushes the address to the stack
    """
    evm = draw(
        EvmBuilder()
        .with_env()
        .with_message()
        .with_stack()
        .with_gas_left()
        .with_running()
        .with_accessed_addresses()
        .with_accessed_storage_keys()
        .with_accounts_to_delete()
        .with_touched_accounts()
        .with_env()
        .build()
    )

    # Choose between state address (80%) or random address (20%)
    use_state_address = draw(st.integers(0, 99)) < 80

    if use_state_address and evm.env.state._main_trie._data:
        # Get address from state if av
        beneficiary = draw(st.sampled_from(list(evm.env.state._main_trie._data.keys())))
    else:
        beneficiary = draw(st.from_type(Address))

    push(evm.stack, U256.from_be_bytes(beneficiary))

    # 20% chance to set beneficiary to originator
    beneficiary_is_originator = draw(st.integers(0, 99)) < 20
    if beneficiary_is_originator:
        evm.message.current_target = beneficiary

    return evm


class TestSystem:
    @given(evm=revert_return_strategy())
    def test_revert(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("revert", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                revert(evm)
            return

        revert(evm)
        assert evm == cairo_result

    @given(evm=revert_return_strategy())
    def test_return(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("return_", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                return_(evm)
            return

        return_(evm)
        assert evm == cairo_result

    @given(evm=beneficiary_from_state())
    def test_selfdestruct(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("selfdestruct", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                selfdestruct(evm)
            return

        selfdestruct(evm)
        assert evm == cairo_result

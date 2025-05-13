import pytest
from ethereum.cancun.fork_types import Address
from ethereum.cancun.vm import Evm
from ethereum.cancun.vm.instructions.system import (
    call,
    callcode,
    create,
    create2,
    delegatecall,
    generic_call,
    generic_create,
    return_,
    revert,
    selfdestruct,
    staticcall,
)
from ethereum_types.numeric import U256, Uint
from hypothesis import given
from hypothesis import strategies as st
from hypothesis.strategies import composite

from cairo_addons.testing.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder
from tests.utils.message_builder import MessageBuilder
from tests.utils.strategies import (
    MAX_MEMORY_SIZE,
    bounded_u256_strategy,
    memory_lite_access_size,
    memory_lite_start_position,
)

local_strategy = (
    EvmBuilder()
    .with_gas_left()
    .with_logs()
    .with_accessed_addresses()
    .with_accessed_storage_keys()
    .with_accounts_to_delete()
    .with_refund_counter()
    .build()
)

evm_stack_memory_gas = EvmBuilder().with_stack().with_memory().with_gas_left().build()
evm_call = (
    EvmBuilder()
    .with_stack()
    .with_message(MessageBuilder().with_block_env().with_tx_env().build())
    .with_memory()
    .with_gas_left()
    .build()
)


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
        evm.stack.push_or_replace_many([size, memory_start])

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
        .with_message(MessageBuilder().with_block_env().with_tx_env().build())
        .with_stack()
        .with_gas_left()
        .with_running()
        .with_accessed_addresses()
        .with_accessed_storage_keys()
        .with_accounts_to_delete()
        .build()
    )

    # Choose between state address (80%) or random address (20%)
    use_state_address = draw(st.integers(0, 99)) < 80

    if use_state_address and evm.env.state._main_trie._data:
        # Get address from state if av
        beneficiary = draw(st.sampled_from(list(evm.env.state._main_trie._data.keys())))
    else:
        beneficiary = draw(st.from_type(Address))

    evm.stack.push_or_replace(U256.from_be_bytes(beneficiary))

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
    @pytest.mark.slow
    def test_selfdestruct(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("selfdestruct", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                selfdestruct(evm)
            return

        selfdestruct(evm)
        assert evm == cairo_result


class TestSystemCairoFile:
    @given(
        evm=local_strategy,
        endowment=...,
        contract_address=...,
        # Restricting to MAX_MEMORY_SIZE to avoid OOG errors which would be caught by the calling function
        memory_start_position=bounded_u256_strategy(max_value=MAX_MEMORY_SIZE),
        memory_size=bounded_u256_strategy(max_value=MAX_MEMORY_SIZE),
    )
    def test_generic_create(
        self,
        cairo_run,
        evm: Evm,
        endowment: U256,
        contract_address: Address,
        memory_start_position: U256,
        memory_size: U256,
    ):
        try:
            cairo_evm = cairo_run(
                "test_generic_create",
                evm,
                endowment,
                contract_address,
                memory_start_position,
                memory_size,
            )
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                generic_create(
                    evm,
                    endowment,
                    contract_address,
                    memory_start_position,
                    memory_size,
                )
            return

        generic_create(
            evm,
            endowment,
            contract_address,
            memory_start_position,
            memory_size,
        )
        assert evm == cairo_evm

    @given(evm=evm_stack_memory_gas)
    def test_create(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("test_create", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                create(evm)
            return

        create(evm)
        assert evm == cairo_result

    @given(evm=evm_stack_memory_gas)
    def test_create2(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("test_create2", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                create2(evm)
            return

        create2(evm)
        assert evm == cairo_result

    @given(
        evm=local_strategy,
        gas=...,
        value=...,
        caller=...,
        to=...,
        code_address=...,
        should_transfer_value=...,
        is_staticcall=...,
        memory_input_start_position=bounded_u256_strategy(max_value=MAX_MEMORY_SIZE),
        memory_input_size=bounded_u256_strategy(max_value=MAX_MEMORY_SIZE),
        memory_output_start_position=bounded_u256_strategy(max_value=MAX_MEMORY_SIZE),
        memory_output_size=bounded_u256_strategy(max_value=MAX_MEMORY_SIZE),
    )
    def test_generic_call(
        self,
        cairo_run,
        evm: Evm,
        gas: Uint,
        value: U256,
        caller: Address,
        to: Address,
        code_address: Address,
        should_transfer_value: bool,
        is_staticcall: bool,
        memory_input_start_position: U256,
        memory_input_size: U256,
        memory_output_start_position: U256,
        memory_output_size: U256,
    ):
        try:
            cairo_evm = cairo_run(
                "test_generic_call",
                evm,
                gas,
                value,
                caller,
                to,
                code_address,
                should_transfer_value,
                is_staticcall,
                memory_input_start_position,
                memory_input_size,
                memory_output_start_position,
                memory_output_size,
            )
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                generic_call(
                    evm,
                    gas,
                    value,
                    caller,
                    to,
                    code_address,
                    should_transfer_value,
                    is_staticcall,
                    memory_input_start_position,
                    memory_input_size,
                    memory_output_start_position,
                    memory_output_size,
                )
            return

        generic_call(
            evm,
            gas,
            value,
            caller,
            to,
            code_address,
            should_transfer_value,
            is_staticcall,
            memory_input_start_position,
            memory_input_size,
            memory_output_start_position,
            memory_output_size,
        )
        assert evm == cairo_evm

    @given(evm=evm_call)
    @pytest.mark.slow
    def test_call(self, cairo_run, evm: Evm):
        # Set depth to 1024 to avoid triggering regular execution flow when entering into generic_call
        # TODO: remove this once we have all opcodes implemented
        evm.message.depth = Uint(1024)
        try:
            cairo_result = cairo_run("test_call", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                call(evm)
            return

        call(evm)
        assert evm == cairo_result

    @given(evm=evm_call)
    @pytest.mark.slow
    def test_callcode(self, cairo_run, evm: Evm):
        # Set depth to 1024 to avoid entering into generic_call, but only testing callcode logic
        evm.message.depth = Uint(1024)
        try:
            cairo_result = cairo_run("test_callcode", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                callcode(evm)
            return

        callcode(evm)
        assert evm == cairo_result

    @given(evm=evm_call)
    @pytest.mark.slow
    def test_delegatecall(self, cairo_run, evm: Evm):
        # Set depth to 1024 to avoid entering into generic_call, but only testing delegatecall logic
        evm.message.depth = Uint(1024)
        try:
            cairo_result = cairo_run("test_delegatecall", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                delegatecall(evm)
            return

        delegatecall(evm)
        assert evm == cairo_result

    @given(evm=evm_call)
    @pytest.mark.slow
    def test_staticcall(self, cairo_run, evm: Evm):
        # Set depth to 1024 to avoid entering into generic_call, but only testing staticcall logic
        evm.message.depth = Uint(1024)
        try:
            cairo_result = cairo_run("test_staticcall", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                staticcall(evm)
            return

        staticcall(evm)
        assert evm == cairo_result

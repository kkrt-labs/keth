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
    staticcall,
)
from ethereum_types.numeric import U256, Uint
from hypothesis import given

from tests.utils.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder
from tests.utils.strategies import MAX_MEMORY_SIZE, bounded_u256_strategy

local_strategy = (
    EvmBuilder()
    .with_gas_left()
    .with_logs()
    .with_accessed_addresses()
    .with_accessed_storage_keys()
    .with_accounts_to_delete()
    .with_touched_accounts()
    .with_refund_counter()
    .build()
)

evm_stack_memory_gas = EvmBuilder().with_stack().with_memory().with_gas_left().build()
evm_call = (
    EvmBuilder()
    .with_stack()
    .with_env()
    .with_message()
    .with_memory()
    .with_gas_left()
    .build()
)


class TestSystem:
    @given(
        evm=local_strategy,
        endowment=...,
        contract_address=...,
        # Restricting to 2** to avoid OOG errors which would be caught by the calling function
        memory_start_position=bounded_u256_strategy(max_value=MAX_MEMORY_SIZE),
        memory_size=bounded_u256_strategy(max_value=MAX_MEMORY_SIZE),
        init_code_gas=...,
    )
    def test_generic_create(
        self,
        cairo_run,
        evm: Evm,
        endowment: U256,
        contract_address: Address,
        memory_start_position: U256,
        memory_size: U256,
        init_code_gas: Uint,
    ):
        try:
            cairo_evm = cairo_run(
                "test_generic_create",
                evm,
                endowment,
                contract_address,
                memory_start_position,
                memory_size,
                init_code_gas,
            )
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                generic_create(
                    evm,
                    endowment,
                    contract_address,
                    memory_start_position,
                    memory_size,
                    init_code_gas,
                )
            return

        generic_create(
            evm,
            endowment,
            contract_address,
            memory_start_position,
            memory_size,
            init_code_gas,
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

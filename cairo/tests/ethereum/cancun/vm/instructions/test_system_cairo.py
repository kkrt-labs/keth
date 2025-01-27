from ethereum_types.numeric import U256, Uint
from hypothesis import given

from ethereum.cancun.fork_types import Address
from ethereum.cancun.vm.instructions.system import generic_call, generic_create
from tests.utils.args_gen import Evm
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

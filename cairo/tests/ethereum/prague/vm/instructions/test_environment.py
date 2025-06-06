from ethereum.crypto.hash import Hash32
from ethereum.exceptions import EthereumException
from ethereum.prague.vm import BlockEnvironment, Evm
from ethereum.prague.vm.instructions.environment import (
    address,
    balance,
    base_fee,
    blob_base_fee,
    blob_hash,
    calldatacopy,
    calldataload,
    calldatasize,
    caller,
    callvalue,
    codecopy,
    codesize,
    extcodecopy,
    extcodehash,
    extcodesize,
    gasprice,
    origin,
    returndatacopy,
    returndatasize,
    self_balance,
)
from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U256
from hypothesis import given
from hypothesis import strategies as st
from hypothesis.strategies import composite, integers

from cairo_addons.testing.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder
from tests.utils.message_builder import MessageBuilder
from tests.utils.strategies import (
    MAX_CODE_SIZE,
    MAX_MEMORY_SIZE,
)
from tests.utils.strategies import address as address_strategy
from tests.utils.strategies import (
    bounded_u256_strategy,
    code,
    empty_state,
    excess_blob_gas,
    memory_lite,
)

block_environment_empty_state = st.builds(
    BlockEnvironment,
    chain_id=...,
    state=empty_state,
    block_gas_limit=...,
    block_hashes=...,
    coinbase=...,
    number=...,
    base_fee_per_gas=...,
    time=...,
    prev_randao=...,
    excess_blob_gas=excess_blob_gas,
    parent_beacon_block_root=st.just(Hash32(Bytes32(b"\x00" * 32))),
)

message_empty_except_calldata = MessageBuilder().with_data(code).build()


evm_environment_strategy = (
    EvmBuilder()
    .with_gas_left()
    .with_message(
        MessageBuilder()
        .with_block_env(block_environment_empty_state)
        .with_tx_env()
        .build()
    )
    .build()
)


@composite
def codecopy_strategy(draw):
    """Generate test cases for the codecopy instruction.

    This strategy generates an EVM instance and the required parameters for codecopy.
    - 8/10 chance: pushes all parameters onto the stack to test normal operation
    - 2/10 chance: use stack already populated with values, mostly to test errors cases
    """
    evm = draw(
        EvmBuilder()
        .with_stack()
        .with_gas_left()
        .with_code(strategy=code)
        .with_memory(strategy=memory_lite)
        .build()
    )
    memory_start_index = draw(bounded_u256_strategy(max_value=MAX_MEMORY_SIZE))
    code_start_index = draw(bounded_u256_strategy(max_value=MAX_CODE_SIZE))
    size = draw(bounded_u256_strategy(max_value=MAX_CODE_SIZE * 2))

    # 80% chance to push valid values onto stack
    should_push = draw(integers(0, 99)) < 80
    if should_push:
        evm.stack.push_or_replace_many([size, code_start_index, memory_start_index])

    return evm


@composite
def calldatacopy_strategy(draw):
    """Generate test cases for the calldatacopy instruction.

    This strategy generates an EVM instance and the required parameters for calldatacopy.
    - 8/10 chance: pushes all parameters onto the stack to test normal operation
    - 2/10 chance: use stack already populated with values, mostly to test error cases
    """
    evm = draw(
        EvmBuilder()
        .with_stack()
        .with_gas_left()
        .with_memory()
        .with_message(strategy=message_empty_except_calldata)
        .build()
    )

    memory_start_index = draw(bounded_u256_strategy(max_value=MAX_MEMORY_SIZE))
    data_start_index = draw(bounded_u256_strategy(max_value=MAX_CODE_SIZE))
    size = draw(bounded_u256_strategy(max_value=MAX_CODE_SIZE * 2))

    # 80% chance to push valid values onto stack
    should_push = draw(integers(0, 99)) < 80
    if should_push:
        evm.stack.push_or_replace_many([size, data_start_index, memory_start_index])

    return evm


@composite
def evm_accessed_addresses_strategy(draw):
    """Strategy to generate an EVM and an address that potentially exists in the state."""
    evm = draw(
        EvmBuilder()
        .with_stack()
        .with_accessed_addresses()
        .with_gas_left()
        .with_message(MessageBuilder().with_block_env().with_tx_env().build())
        .build()
    )
    state = evm.message.block_env.state

    address_options = []

    # Add addresses from main trie if any exist
    if state._main_trie._data:
        address_options.append(st.sampled_from(list(state._main_trie._data.keys())))
    address_options.append(address_strategy)

    # Draw an address from one of the available options
    address = draw(st.one_of(*address_options))
    evm.stack.push_or_replace(U256.from_be_bytes(address))

    return evm


class TestEnvironmentInstructions:
    @given(evm=evm_environment_strategy)
    def test_address(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("address", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                address(evm)
            return

        address(evm)
        assert evm == cairo_result

    @given(evm=evm_accessed_addresses_strategy())
    def test_balance(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("balance", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                balance(evm)
            return

        balance(evm)
        assert evm == cairo_result

    @given(evm=evm_environment_strategy)
    def test_origin(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("origin", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                origin(evm)
            return

        origin(evm)
        assert evm == cairo_result

    @given(evm=evm_environment_strategy)
    def test_caller(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("caller", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                caller(evm)
            return

        caller(evm)
        assert evm == cairo_result

    @given(evm=evm_environment_strategy)
    def test_callvalue(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("callvalue", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                callvalue(evm)
            return

        callvalue(evm)
        assert evm == cairo_result

    @given(evm=evm_environment_strategy)
    def test_codesize(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("codesize", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                codesize(evm)
            return

        codesize(evm)
        assert evm == cairo_result

    @given(evm=evm_environment_strategy)
    def test_gasprice(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("gasprice", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                gasprice(evm)
            return

        gasprice(evm)
        assert evm == cairo_result

    @given(evm=evm_environment_strategy)
    def test_returndatasize(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("returndatasize", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                returndatasize(evm)
            return

        returndatasize(evm)
        assert evm == cairo_result

    @given(
        evm=EvmBuilder()
        .with_memory()
        .with_gas_left()
        .with_message(
            MessageBuilder()
            .with_block_env(block_environment_empty_state)
            .with_tx_env()
            .build()
        )
        .with_return_data()
        .with_capped_values_stack()
        .build()
    )
    def test_returndatacopy(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("returndatacopy", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                returndatacopy(evm)
            return

        returndatacopy(evm)
        assert evm == cairo_result

    @given(evm=evm_environment_strategy)
    def test_self_balance(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("self_balance", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                self_balance(evm)
            return

        self_balance(evm)
        assert evm == cairo_result

    @given(evm=evm_environment_strategy)
    def test_base_fee(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("base_fee", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                base_fee(evm)
            return

        base_fee(evm)
        assert evm == cairo_result

    @given(evm=evm_environment_strategy)
    def test_blob_hash(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("blob_hash", evm)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                blob_hash(evm)
            return

        blob_hash(evm)
        assert evm == cairo_result

    @given(evm=codecopy_strategy())
    def test_codecopy(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("codecopy", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                codecopy(evm)
            return

        codecopy(evm)
        assert evm == cairo_result

    @given(evm=evm_accessed_addresses_strategy())
    def test_extcodesize(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("extcodesize", evm)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                extcodesize(evm)
            return

        extcodesize(evm)
        assert evm == cairo_result

    @given(evm=evm_accessed_addresses_strategy())
    def test_extcodecopy(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("extcodecopy", evm)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                extcodecopy(evm)
            return

        extcodecopy(evm)
        assert evm == cairo_result

    @given(evm=evm_accessed_addresses_strategy())
    def test_extcodehash(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("extcodehash", evm)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                extcodehash(evm)
            return

        extcodehash(evm)
        assert evm == cairo_result

    @given(evm=evm_environment_strategy)
    def test_blob_base_fee(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("blob_base_fee", evm)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                blob_base_fee(evm)
            return

        blob_base_fee(evm)
        assert evm == cairo_result

    @given(
        evm=EvmBuilder()
        .with_stack()
        .with_gas_left()
        .with_message(strategy=message_empty_except_calldata)
        .build()
    )
    def test_calldataload(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("calldataload", evm)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                calldataload(evm)
            return

        calldataload(evm)
        assert evm == cairo_result

    @given(evm=calldatacopy_strategy())
    def test_calldatacopy(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("calldatacopy", evm)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                calldatacopy(evm)
            return

        calldatacopy(evm)
        assert evm == cairo_result

    @given(
        evm=EvmBuilder()
        .with_stack()
        .with_gas_left()
        .with_message(strategy=message_empty_except_calldata)
        .build()
    )
    def test_calldatasize(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("calldatasize", evm)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                calldatasize(evm)
            return

        calldatasize(evm)
        assert evm == cairo_result

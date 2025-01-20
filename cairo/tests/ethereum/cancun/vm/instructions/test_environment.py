from ethereum_types.numeric import U256
from hypothesis import given, reproduce_failure
from hypothesis import strategies as st
from hypothesis.strategies import composite, integers

from ethereum.cancun.state import TransientStorage
from ethereum.cancun.vm.exceptions import ExceptionalHalt
from ethereum.cancun.vm.instructions.environment import (
    address,
    balance,
    base_fee,
    blob_hash,
    caller,
    callvalue,
    codecopy,
    codesize,
    extcodecopy,
    extcodehash,
    extcodesize,
    gasprice,
    origin,
    returndatasize,
    self_balance,
)
from ethereum.cancun.vm.stack import push
from tests.utils.args_gen import Environment, Evm, VersionedHash
from tests.utils.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder
from tests.utils.strategies import MAX_CODE_SIZE
from tests.utils.strategies import address as address_strategy
from tests.utils.strategies import (
    code,
    empty_state,
    memory_lite,
    memory_lite_start_position,
)

environment_empty_state = st.builds(
    Environment,
    caller=...,
    block_hashes=st.just([]),
    origin=...,
    coinbase=...,
    number=...,
    base_fee_per_gas=...,
    gas_limit=...,
    gas_price=...,
    time=...,
    prev_randao=...,
    state=empty_state,
    chain_id=...,
    excess_blob_gas=...,
    blob_versioned_hashes=st.lists(
        st.from_type(VersionedHash), min_size=0, max_size=5
    ).map(tuple),
    transient_storage=st.just(TransientStorage()),
)

evm_environment_strategy = (
    EvmBuilder().with_gas_left().with_env(environment_empty_state).build()
)

code_access_size_strategy = st.integers(min_value=0, max_value=MAX_CODE_SIZE).map(U256)
code_start_index_strategy = code_access_size_strategy


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
    memory_start_index = draw(memory_lite_start_position)
    code_start_index = draw(code_start_index_strategy)
    size = draw(code_access_size_strategy)

    # 80% chance to push valid values onto stack
    should_push = draw(integers(0, 99)) < 80
    if should_push:
        push(evm.stack, U256(size))
        push(evm.stack, U256(code_start_index))
        push(evm.stack, U256(memory_start_index))

    return evm


@composite
def evm_accessed_addresses_strategy(draw):
    """Strategy to generate an EVM and an address that potentially exists in the state."""
    evm = draw(
        EvmBuilder()
        .with_stack()
        .with_accessed_addresses()
        .with_gas_left()
        .with_env()
        .build()
    )
    state = evm.env.state

    address_options = []

    # Add addresses from main trie if any exist
    if state._main_trie._data:
        address_options.append(st.sampled_from(list(state._main_trie._data.keys())))
    address_options.append(address_strategy)

    # Draw an address from one of the available options
    address = draw(st.one_of(*address_options))
    push(evm.stack, U256.from_be_bytes(address))

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
        except ExceptionalHalt as cairo_error:
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
        except ExceptionalHalt as cairo_error:
            with strict_raises(type(cairo_error)):
                extcodesize(evm)
            return

        extcodesize(evm)
        assert evm == cairo_result

    @given(evm=evm_accessed_addresses_strategy())
    def test_extcodecopy(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("extcodecopy", evm)
        except ExceptionalHalt as cairo_error:
            with strict_raises(type(cairo_error)):
                extcodecopy(evm)
            return

        extcodecopy(evm)
        assert evm == cairo_result

    @reproduce_failure(
        "6.123.17",
        b"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",
    )
    @given(evm=evm_accessed_addresses_strategy())
    def test_extcodehash(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("extcodehash", evm)
        except ExceptionalHalt as cairo_error:
            with strict_raises(type(cairo_error)):
                extcodehash(evm)
            return

        extcodehash(evm)
        assert evm == cairo_result

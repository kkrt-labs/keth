from hypothesis import given
from hypothesis import strategies as st

from ethereum.cancun.state import TransientStorage
from ethereum.cancun.vm.instructions.environment import (
    address,
    balance,
    base_fee,
    caller,
    callvalue,
    codesize,
    gasprice,
    origin,
    returndatasize,
    self_balance,
)
from tests.utils.args_gen import Environment, Evm, VersionedHash
from tests.utils.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder
from tests.utils.strategies import empty_state

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

    @given(
        evm=EvmBuilder()
        .with_stack()
        .with_accessed_addresses()
        .with_gas_left()
        .with_env(environment_empty_state)
        .build()
    )
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

from ethereum.cancun.fork_types import EMPTY_ACCOUNT
from ethereum.cancun.state import set_account
from ethereum.cancun.vm import (
    Evm,
    incorporate_child_on_error,
    incorporate_child_on_success,
)
from ethereum.cancun.vm.precompiled_contracts import RIPEMD160_ADDRESS
from hypothesis import given

from cairo_addons.testing.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder

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

local_strategy_with_env = (
    EvmBuilder()
    .with_gas_left()
    .with_logs()
    .with_accessed_addresses()
    .with_accessed_storage_keys()
    .with_accounts_to_delete()
    .with_touched_accounts()
    .with_refund_counter()
    .with_env()
    .build()
)


class TestVm:
    @given(evm=local_strategy, child_evm=local_strategy)
    def test_incorporate_child_on_success(self, cairo_run, evm: Evm, child_evm: Evm):
        try:
            evm_cairo = cairo_run("incorporate_child_on_success", evm, child_evm)
        except Exception as e:
            with strict_raises(type(e)):
                incorporate_child_on_success(evm, child_evm)
            return

        incorporate_child_on_success(evm, child_evm)
        assert evm_cairo == evm

    @given(evm=local_strategy, child_evm=local_strategy)
    def test_incorporate_child_on_error(self, cairo_run, evm: Evm, child_evm: Evm):
        try:
            evm_cairo = cairo_run("incorporate_child_on_error", evm, child_evm)
        except Exception as e:
            with strict_raises(type(e)):
                incorporate_child_on_error(evm, child_evm)
            return

        incorporate_child_on_error(evm, child_evm)
        assert evm_cairo == evm

    @given(
        evm=local_strategy_with_env,
        child_evm=local_strategy_with_env,
    )
    def test_incorporate_child_on_success_with_empty_account(
        self, cairo_run, evm: Evm, child_evm: Evm
    ):
        set_account(evm.env.state, child_evm.message.current_target, EMPTY_ACCOUNT)
        try:
            evm_cairo = cairo_run("incorporate_child_on_success", evm, child_evm)
        except Exception as e:
            with strict_raises(type(e)):
                incorporate_child_on_success(evm, child_evm)
            return

        incorporate_child_on_success(evm, child_evm)
        assert evm_cairo == evm

    @given(
        evm=local_strategy_with_env,
        child_evm=local_strategy_with_env,
    )
    def test_incorporate_child_on_error_with_ripemd_target_exists_and_is_empty(
        self, cairo_run, evm: Evm, child_evm: Evm
    ):
        child_evm.message.current_target = RIPEMD160_ADDRESS
        set_account(evm.env.state, child_evm.message.current_target, EMPTY_ACCOUNT)
        try:
            evm_cairo = cairo_run("incorporate_child_on_error", evm, child_evm)
        except Exception as e:
            with strict_raises(type(e)):
                incorporate_child_on_error(evm, child_evm)
            return

        incorporate_child_on_error(evm, child_evm)
        assert evm_cairo == evm

    @given(
        evm=local_strategy_with_env,
        child_evm=local_strategy_with_env,
    )
    def test_incorporate_child_on_error_with_ripemd_target(
        self, cairo_run, evm: Evm, child_evm: Evm
    ):
        child_evm.message.current_target = RIPEMD160_ADDRESS
        try:
            evm_cairo = cairo_run("incorporate_child_on_error", evm, child_evm)
        except Exception as e:
            with strict_raises(type(e)):
                incorporate_child_on_error(evm, child_evm)
            return

        incorporate_child_on_error(evm, child_evm)
        assert evm_cairo == evm

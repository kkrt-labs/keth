from ethereum.cancun.fork_types import EMPTY_ACCOUNT
from ethereum.cancun.state import set_account
from ethereum.cancun.vm import (
    Evm,
    incorporate_child_on_error,
    incorporate_child_on_success,
)
from hypothesis import given

from tests.utils.errors import strict_raises
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
        evm=EvmBuilder()
        .with_gas_left()
        .with_logs()
        .with_accessed_addresses()
        .with_accessed_storage_keys()
        .with_accounts_to_delete()
        .with_touched_accounts()
        .with_refund_counter()
        .with_env()
        .build(),
        child_evm=EvmBuilder()
        .with_gas_left()
        .with_logs()
        .with_accessed_addresses()
        .with_accessed_storage_keys()
        .with_accounts_to_delete()
        .with_touched_accounts()
        .with_refund_counter()
        .with_env()
        .build(),
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

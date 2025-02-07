from ethereum.cancun.fork_types import Account, Address
from ethereum.cancun.state import set_account, set_storage
from ethereum.cancun.trie import copy_trie
from ethereum.cancun.vm import Evm
from ethereum.cancun.vm.instructions.storage import sload, sstore, tload, tstore
from ethereum.cancun.vm.stack import push
from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U256
from hypothesis import given
from hypothesis import strategies as st

from tests.utils.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder
from tests.utils.message_builder import MessageBuilder

evm_storage_strategy = (
    EvmBuilder()
    .with_stack()
    .with_gas_left()
    .with_env()
    .with_accessed_storage_keys()
    .with_message(MessageBuilder().with_is_static().build())
    .build()
)


class TestStorage:
    @given(evm=evm_storage_strategy)
    def test_sload(self, cairo_run, evm: Evm):
        try:
            cairo_evm = cairo_run("sload", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                sload(evm)
            return

        sload(evm)
        assert evm == cairo_evm

    @given(evm=evm_storage_strategy)
    def test_sstore(self, cairo_run, evm: Evm):
        try:
            cairo_evm = cairo_run("sstore", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                sstore(evm)
            return
        sstore(evm)
        assert evm == cairo_evm

    @given(
        evm=evm_storage_strategy,
        key=...,
        value=...,
        address=...,
        account=...,
        current_value_is_zero=...,
    )
    def test_sstore_with_target_address_in_accessed_storage_keys_and_current_value_diff_new_value(
        self,
        cairo_run,
        evm: Evm,
        key: Bytes32,
        value: U256,
        address: Address,
        account: Account,
        current_value_is_zero: bool,
    ):
        set_account(
            evm.env.state,
            address,
            account,
        )
        evm.message.current_target = address
        evm.accessed_storage_keys.add((evm.message.current_target, key))
        set_storage(
            evm.env.state,
            evm.message.current_target,
            key,
            value if not current_value_is_zero else U256(0),
        )
        # modify snapshot to match the new state
        evm.env.state._snapshots.insert(
            0,
            (
                copy_trie(evm.env.state._main_trie),
                {
                    addr: copy_trie(trie)
                    for addr, trie in evm.env.state._storage_tries.items()
                },
            ),
        )
        push(evm.stack, value)
        push(evm.stack, U256.from_be_bytes(key))

        try:
            cairo_evm = cairo_run("sstore", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                sstore(evm)
            return
        sstore(evm)
        assert evm == cairo_evm

    @given(evm=evm_storage_strategy)
    def test_tload(self, cairo_run, evm: Evm):
        try:
            cairo_evm = cairo_run("tload", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                tload(evm)
            return

        tload(evm)
        assert evm == cairo_evm

    @given(evm=evm_storage_strategy)
    def test_tstore(self, cairo_run, evm: Evm):
        try:
            cairo_evm = cairo_run("tstore", evm)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                tstore(evm)
            return
        tstore(evm)
        assert evm == cairo_evm

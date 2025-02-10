from itertools import product

from ethereum.cancun.fork_types import Account, Address
from ethereum.cancun.state import set_account, set_storage
from ethereum.cancun.trie import copy_trie
from ethereum.cancun.vm import Evm
from ethereum.cancun.vm.instructions.storage import sload, sstore, tload, tstore
from ethereum.cancun.vm.stack import push
from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U256, Uint
from hypothesis import given
from hypothesis import strategies as st
from hypothesis.strategies import composite

from cairo_addons.testing.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder
from tests.utils.message_builder import MessageBuilder
from tests.utils.strategies import account_strategy

evm_storage_strategy = (
    EvmBuilder()
    .with_stack()
    .with_gas_left()
    .with_env()
    .with_accessed_storage_keys()
    .with_message(MessageBuilder().with_is_static().build())
    .build()
)


@composite
def sstore_strategy(draw):
    evm = draw(evm_storage_strategy)
    is_key_accessed = draw(st.booleans())
    if is_key_accessed and evm.stack:
        account = draw(account_strategy)
        # Ensure the account exists and the key is accessed
        set_account(
            evm.env.state,
            evm.message.current_target,
            account,
        )
        evm.accessed_storage_keys.add(
            (evm.message.current_target, evm.stack[-1].to_be_bytes32())
        )
    return evm


@composite
def sstore_refund_counter_strategy(draw):
    tuples = list(product([U256(0), U256(1)], repeat=3))
    return draw(st.sampled_from(tuples))


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

    @given(evm=sstore_strategy())
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
        evm=EvmBuilder().build(),
        address=...,
        key=...,
        data=sstore_refund_counter_strategy(),
    )
    def test_sstore_refund_counter(
        self,
        cairo_run,
        address: Address,
        key: Bytes32,
        evm: Evm,
        data,
    ):
        """
        This test ensures all cases for the refund counter are tested.
        That is why the evm is not fuzzed.
        """
        evm.gas_left = Uint(30_000_000)  # avoid OutOfGasError
        new_value, current_value, original_value = data

        # Ensure the account exists and is the current target
        account = Account(balance=U256(0), nonce=U256(0), code=b"6001600101")
        set_account(
            evm.env.state,
            address,
            account,
        )
        evm.message.current_target = address
        # Set the original value
        set_storage(
            evm.env.state,
            evm.message.current_target,
            key,
            original_value,
        )
        # Take a snapshot of the state
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
        # Set the current value
        set_storage(
            evm.env.state,
            evm.message.current_target,
            key,
            current_value,
        )
        # Push the new value and the key to the stack
        push(evm.stack, new_value)
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

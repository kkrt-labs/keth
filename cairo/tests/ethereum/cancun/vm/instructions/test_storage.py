from collections import defaultdict
from itertools import product

from ethereum.cancun.fork_types import EMPTY_ACCOUNT, Account, Address
from ethereum.cancun.state import set_account, set_storage
from ethereum.cancun.trie import Trie, copy_trie, root
from ethereum.cancun.vm import Evm
from ethereum.cancun.vm.gas import (
    GAS_COLD_SLOAD,
    GAS_STORAGE_CLEAR_REFUND,
    GAS_STORAGE_SET,
    GAS_STORAGE_UPDATE,
    GAS_WARM_ACCESS,
)
from ethereum.cancun.vm.instructions.storage import sload, sstore, tload, tstore
from ethereum.crypto.hash import keccak256
from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U256, Uint
from hypothesis import given
from hypothesis import strategies as st
from hypothesis.strategies import composite
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

from cairo_addons.testing.errors import strict_raises
from keth_types.types import EMPTY_BYTES_HASH, EMPTY_TRIE_HASH
from tests.utils.evm_builder import EvmBuilder
from tests.utils.message_builder import MessageBuilder
from tests.utils.strategies import felt

evm_storage_strategy = (
    EvmBuilder()
    .with_stack()
    .with_gas_left()
    .with_accessed_storage_keys()
    .with_message(
        MessageBuilder().with_block_env().with_tx_env().with_is_static().build()
    )
    .build()
)


@composite
def sstore_strategy(draw):
    evm = draw(evm_storage_strategy)
    is_key_accessed = draw(st.booleans())
    if is_key_accessed and evm.stack:
        account = draw(st.from_type(Account))
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

    @given(evm=evm_storage_strategy, address=..., key=..., value=...)
    def test_sload_on_filled_storage(
        self, cairo_run, evm: Evm, address: Address, key: Bytes32, value: U256
    ):
        """
        This test ensures that sload won't be used on an empty storage.
        """
        state = evm.message.block_env.state

        # Set an empty account in state
        set_account(state, address, EMPTY_ACCOUNT)
        # Set the proper storage value
        set_storage(state, address, key, value)
        # Set the proper account with the appropriate storage root
        if address in state._storage_tries:
            account_storage_root = root(state._storage_tries[address])
        else:
            account_storage_root = EMPTY_TRIE_HASH
        set_account(
            state,
            address,
            Account(
                balance=U256(1),
                nonce=U256(2),
                code=b"",
                storage_root=account_storage_root,
                code_hash=EMPTY_BYTES_HASH,
            ),
        )
        evm.stack.push_or_replace(U256.from_be_bytes(key))
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

        # Ensure an account exists in state to fill the storage
        evm.message.current_target = address
        set_account(
            evm.message.block_env.state,
            address,
            EMPTY_ACCOUNT,
        )
        # Set the original value
        set_storage(
            evm.message.block_env.state,
            address,
            key,
            original_value,
        )
        # Fill with the proper account values - ensure it's the current target
        code = b"6001600101"
        code_hash = keccak256(code)
        if address in evm.message.block_env.state._storage_tries:
            storage_root = root(evm.message.block_env.state._storage_tries[address])
        else:
            storage_root = EMPTY_TRIE_HASH
        account = Account(
            balance=U256(0),
            nonce=U256(0),
            code=code,
            code_hash=code_hash,
            storage_root=storage_root,
        )
        set_account(
            evm.message.block_env.state,
            address,
            account,
        )
        # Take a snapshot of the state
        evm.message.block_env.state._snapshots.insert(
            0,
            (
                copy_trie(evm.message.block_env.state._main_trie),
                defaultdict(
                    lambda: Trie(
                        secured=True,
                        default=U256(0),
                        _data=defaultdict(lambda: U256(0)),
                    ),
                    {
                        addr: copy_trie(trie)
                        for addr, trie in evm.message.block_env.state._storage_tries.items()
                    },
                ),
            ),
        )
        # Set the current value
        set_storage(
            evm.message.block_env.state,
            evm.message.current_target,
            key,
            current_value,
        )
        # Push the new value and the key to the stack
        evm.stack.push_or_replace_many([new_value, U256.from_be_bytes(key)])

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

    @given(
        current_refund_counter=felt,
        original_value=...,
        current_value=...,
        new_value=...,
    )
    def test_calculate_refund_counter_current_eq_new(
        self,
        cairo_run,
        current_refund_counter,
        original_value: U256,
        current_value: U256,
        new_value: U256,
    ):
        res_cairo = cairo_run(
            "_calculate_refund_counter_current_eq_new",
            current_refund_counter,
            original_value,
            current_value,
            new_value,
            U256(0),
        )
        res = _calculate_refund_counter_current_eq_new(
            current_refund_counter,
            original_value,
            current_value,
            new_value,
        )
        assert int(res) % DEFAULT_PRIME == int(res_cairo)


# see https://github.com/ethereum/execution-specs/blob/6e652281164025f1f4227f6e5b0036c1bbd27347/src/ethereum/cancun/vm/instructions/storage.py#L104
def _calculate_refund_counter_current_eq_new(
    current_refund_counter: Uint,
    original_value: U256,
    current_value: U256,
    new_value: U256,
):
    if original_value != 0 and current_value != 0 and new_value == 0:
        # Storage is cleared for the first time in the transaction
        current_refund_counter += GAS_STORAGE_CLEAR_REFUND

    if original_value != 0 and current_value == 0:
        # Gas refund issued earlier to be reversed
        current_refund_counter -= GAS_STORAGE_CLEAR_REFUND

    if original_value == new_value:
        # Storage slot being restored to its original value
        if original_value == 0:
            # Slot was originally empty and was SET earlier
            current_refund_counter += GAS_STORAGE_SET - GAS_WARM_ACCESS
        else:
            # Slot was originally non-empty and was UPDATED earlier
            current_refund_counter += (
                GAS_STORAGE_UPDATE - GAS_COLD_SLOAD - GAS_WARM_ACCESS
            )

    return current_refund_counter

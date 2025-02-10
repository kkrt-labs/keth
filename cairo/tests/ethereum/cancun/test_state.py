import copy
from typing import Optional

import pytest
from ethereum.cancun.fork_types import EMPTY_ACCOUNT, Account, Address
from ethereum.cancun.state import (
    account_exists,
    account_exists_and_is_empty,
    account_has_code_or_nonce,
    account_has_storage,
    begin_transaction,
    commit_transaction,
    destroy_account,
    destroy_storage,
    destroy_touched_empty_accounts,
    get_account,
    get_account_optional,
    get_storage,
    get_storage_original,
    get_transient_storage,
    increment_nonce,
    is_account_alive,
    is_account_empty,
    mark_account_created,
    move_ether,
    process_withdrawal,
    rollback_transaction,
    set_account,
    set_account_balance,
    set_code,
    set_storage,
    set_transient_storage,
    touch_account,
)
from ethereum.cancun.trie import Trie, copy_trie
from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U256
from hypothesis import given, settings
from hypothesis import strategies as st
from hypothesis.strategies import composite

from cairo_addons.testing.errors import strict_raises
from tests.utils.args_gen import State, TransientStorage, Withdrawal
from tests.utils.strategies import (
    address,
    bytes32,
    code,
    state,
    transient_storage,
    trie_strategy,
)


@composite
def state_and_address_and_optional_key(
    draw, state_strategy=state, address_strategy=address, key_strategy=None
):
    state = draw(state_strategy)

    # For address selection, shuffle from one of the following strategies
    address_options = []
    if state._main_trie._data:
        address_options.append(st.sampled_from(list(state._main_trie._data.keys())))
    if state.created_accounts:
        address_options.append(st.sampled_from(list(state.created_accounts)))
    address_options.append(address_strategy)

    address = draw(st.one_of(*address_options))

    # For key selection, use key_strategy if no storage keys for this address
    if key_strategy is None:
        return state, address

    storage = state._storage_tries.get(address)
    key_options = (
        [st.sampled_from(list(storage._data.keys())), key_strategy]
        if storage is not None and storage._data != {}
        else [key_strategy]
    )
    key = draw(st.one_of(*key_options))

    return state, address, key


@composite
def state_with_snapshots(draw):
    """
    Generate a State instance with up to 10 different snapshots.
    Each snapshot builds on top of the previous one, with up to 5 new entries per snapshot.
    """
    base_state = draw(state)
    num_snapshots = draw(st.integers(min_value=0, max_value=5))

    # Start with base state's tries
    current_main_trie = base_state._main_trie
    current_storage_tries = copy.deepcopy(base_state._storage_tries)
    snapshots = []

    for _ in range(num_snapshots):
        snapshots.append((current_main_trie, current_storage_tries))
        # Add up to 5 new entries to main_trie
        new_accounts = draw(
            st.dictionaries(keys=address, values=st.from_type(Account), max_size=5)
        )
        main_trie_copy = copy_trie(current_main_trie)
        main_trie_copy._data.update(new_accounts)

        # Add up to 5 new storage tries or update existing ones
        new_storage_tries = draw(
            st.dictionaries(
                keys=address,
                values=trie_strategy(Trie[Bytes32, U256], min_size=1),
                max_size=5,
            )
        )
        storage_tries = copy.deepcopy(current_storage_tries)
        # Deep update - merge inner tries instead of overwriting
        for addr, new_trie in new_storage_tries.items():
            if addr in storage_tries:
                storage_tries[addr]._data.update(new_trie._data)
            else:
                storage_tries[addr] = new_trie

        # Update current state for next iteration
        current_main_trie = main_trie_copy
        current_storage_tries = storage_tries

    return State(
        _main_trie=current_main_trie,
        _storage_tries=current_storage_tries,
        _snapshots=snapshots,
        created_accounts=base_state.created_accounts,
    )


@composite
def transient_storage_with_snapshots(draw):
    """
    Generate a TransientStorage instance with up to 10 different snapshots.
    Each snapshot builds on top of the previous one, with up to 5 new entries per snapshot.
    """
    base_transient_storage = draw(transient_storage)
    num_snapshots = draw(st.integers(min_value=0, max_value=5))

    # Start with base transient storage tries
    current_tries = copy.deepcopy(base_transient_storage._tries)
    snapshots = []

    for _ in range(num_snapshots):
        snapshots.append(current_tries)
        # Add up to 5 new tries or update existing ones
        new_tries = draw(
            st.dictionaries(
                keys=address,
                values=trie_strategy(Trie[Bytes32, U256], min_size=1),
                max_size=5,
            )
        )
        tries = copy.deepcopy(current_tries)
        # Deep update - merge inner tries instead of overwriting
        for addr, new_trie in new_tries.items():
            if addr in tries:
                tries[addr]._data.update(new_trie._data)
            else:
                tries[addr] = new_trie

        # Update current tries for next iteration
        current_tries = tries

    return TransientStorage(_tries=current_tries, _snapshots=snapshots)


@composite
def transient_storage_and_address_and_optional_key(
    draw,
    transient_storage_strategy=transient_storage,
    address_strategy=address,
    key_strategy=None,
):
    transient_storage = draw(transient_storage_strategy)

    # Generate address options for sampling
    address_options = []
    if transient_storage._tries:
        address_options.append(st.sampled_from(list(transient_storage._tries.keys())))
    address_options.append(address_strategy)

    # Draw an address from the options
    address = draw(st.one_of(*address_options))

    if key_strategy is None:
        return transient_storage, address

    # Shuffle from a random key of the address, if it exists
    key_options = []
    if address in transient_storage._tries:
        key_options.append(
            st.sampled_from(list(transient_storage._tries[address]._data.keys()))
        )
    key_options.append(key_strategy)
    key = draw(st.one_of(*key_options))

    return transient_storage, address, key


@composite
def touched_accounts_strategy(
    draw,
    state_strategy=state,
    address_strategy=address,
):
    state = draw(state_strategy)

    # Generate a list of addresses that includes both existing accounts and random addresses
    address_options = []
    if state._main_trie._data:
        address_options.append(st.sampled_from(list(state._main_trie._data.keys())))
    address_options.append(address_strategy)

    # Draw a list of addresses and convert to a set
    num_addresses = draw(st.integers(min_value=0, max_value=10))
    addresses = draw(
        st.sets(
            st.one_of(*address_options), min_size=num_addresses, max_size=num_addresses
        )
    )

    return state, addresses


class TestStateAccounts:
    @given(data=state_and_address_and_optional_key())
    def test_get_account(self, cairo_run, data):
        state, address = data
        state_cairo, result_cairo = cairo_run("get_account", state, address)
        assert result_cairo == get_account(state, address)
        assert state_cairo == state

    @given(data=state_and_address_and_optional_key())
    def test_get_account_optional(self, cairo_run, data):
        state, address = data
        state_cairo, result_cairo = cairo_run("get_account_optional", state, address)
        assert result_cairo == get_account_optional(state, address)
        assert state_cairo == state

    @given(data=state_and_address_and_optional_key(), account=...)
    def test_set_account(self, cairo_run, data, account: Optional[Account]):
        state, address = data
        state_cairo = cairo_run("set_account", state, address, account)
        set_account(state, address, account)
        assert state_cairo == state

    @given(
        data=state_and_address_and_optional_key(), recipient_address=address, amount=...
    )
    def test_move_ether(
        self, cairo_run, data, recipient_address: Address, amount: U256
    ):
        state, sender_address = data
        try:
            state_cairo = cairo_run(
                "move_ether", state, sender_address, recipient_address, amount
            )
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                move_ether(state, sender_address, recipient_address, amount)
            return
        move_ether(state, sender_address, recipient_address, amount)
        assert state_cairo == state

    @given(data=state_and_address_and_optional_key(), withdrawal=...)
    def test_process_withdrawal(self, cairo_run, data, withdrawal: Withdrawal):
        state, _ = data
        try:
            state_cairo = cairo_run("process_withdrawal", state, withdrawal)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                process_withdrawal(state, withdrawal)
            return
        process_withdrawal(state, withdrawal)
        assert state_cairo == state

    @given(data=state_and_address_and_optional_key())
    def test_destroy_account(self, cairo_run, data):
        state, address = data
        state_cairo = cairo_run("destroy_account", state, address)
        destroy_account(state, address)
        assert state_cairo == state

    @given(data=state_and_address_and_optional_key())
    def test_account_has_code_or_nonce(self, cairo_run, data):
        state, address = data
        state_cairo, result_cairo = cairo_run(
            "account_has_code_or_nonce", state, address
        )
        assert result_cairo == account_has_code_or_nonce(state, address)
        assert state_cairo == state

    @given(data=state_and_address_and_optional_key())
    def test_account_has_storage(self, cairo_run, data):
        state, address = data
        state_cairo, result_cairo = cairo_run("account_has_storage", state, address)
        assert result_cairo == account_has_storage(state, address)
        assert state_cairo == state

    @given(data=state_and_address_and_optional_key())
    def test_account_exists(self, cairo_run, data):
        state, address = data
        state_cairo, result_cairo = cairo_run("account_exists", state, address)
        assert result_cairo == account_exists(state, address)
        assert state_cairo == state

    @given(data=state_and_address_and_optional_key())
    def test_is_account_empty(self, cairo_run, data):
        state, address = data
        state_cairo, result_cairo = cairo_run("is_account_empty", state, address)
        assert result_cairo == is_account_empty(state, address)
        assert state_cairo == state

    @given(data=state_and_address_and_optional_key())
    def test_mark_account_created(self, cairo_run, data):
        state, address = data
        state_cairo = cairo_run("mark_account_created", state, address)
        mark_account_created(state, address)
        assert state_cairo == state

    @given(data=state_and_address_and_optional_key())
    def test_account_exists_and_is_empty(self, cairo_run, data):
        state, address = data
        state_cairo, result_cairo = cairo_run(
            "account_exists_and_is_empty", state, address
        )
        assert result_cairo == account_exists_and_is_empty(state, address)
        assert state_cairo == state

    @given(data=state_and_address_and_optional_key())
    def test_is_account_alive(self, cairo_run, data):
        state, address = data
        state_cairo, result_cairo = cairo_run("is_account_alive", state, address)
        assert result_cairo == is_account_alive(state, address)
        assert state_cairo == state

    @given(
        data=state_and_address_and_optional_key(),
        code=code,
    )
    def test_set_code(self, cairo_run, data, code: bytes):
        state, address = data
        state_cairo = cairo_run("set_code", state, address, code)
        set_code(state, address, code)
        assert state_cairo == state

    @given(
        data=state_and_address_and_optional_key(),
        amount=...,
    )
    def test_set_account_balance(self, cairo_run, data, amount: U256):
        state, address = data
        state_cairo = cairo_run("set_account_balance", state, address, amount)
        set_account_balance(state, address, amount)
        assert state_cairo == state

    @given(data=state_and_address_and_optional_key())
    def test_increment_nonce(self, cairo_run, data):
        state, address = data
        state_cairo = cairo_run("increment_nonce", state, address)
        increment_nonce(state, address)
        assert state_cairo == state

    @given(data=state_and_address_and_optional_key())
    def test_touch_account(self, cairo_run, data):
        state, address = data
        state_cairo = cairo_run("touch_account", state, address)
        touch_account(state, address)
        assert state_cairo == state

    @given(data=touched_accounts_strategy())
    def test_destroy_touched_empty_accounts(self, cairo_run, data):
        state, touched_accounts = data
        state_cairo = cairo_run(
            "destroy_touched_empty_accounts", state, touched_accounts
        )
        destroy_touched_empty_accounts(state, touched_accounts)
        assert state_cairo == state

    @given(data=touched_accounts_strategy(), address=...)
    def test_destroy_touched_empty_accounts_with_empty_account(
        self, cairo_run, data, address: Address
    ):
        state, touched_accounts = data
        touched_accounts.add(address)
        set_account(state, address, EMPTY_ACCOUNT)
        state_cairo = cairo_run(
            "destroy_touched_empty_accounts", state, touched_accounts
        )
        destroy_touched_empty_accounts(state, touched_accounts)
        assert state_cairo == state


class TestStateStorage:
    @given(data=state_and_address_and_optional_key(key_strategy=bytes32))
    def test_get_storage_original(self, cairo_run, data):
        state, address, key = data
        state_cairo, result_cairo = cairo_run(
            "get_storage_original", state, address, key
        )
        assert result_cairo == get_storage_original(state, address, key)
        assert state_cairo == state

    @given(data=state_and_address_and_optional_key(key_strategy=bytes32))
    def test_get_storage(
        self,
        cairo_run,
        data,
    ):
        state, address, key = data
        state_cairo, result_cairo = cairo_run("get_storage", state, address, key)
        assert result_cairo == get_storage(state, address, key)
        assert state_cairo == state

    @given(data=state_and_address_and_optional_key(key_strategy=bytes32), value=...)
    def test_set_storage(self, cairo_run, data, value: U256):
        state, address, key = data
        try:
            state_cairo = cairo_run("set_storage", state, address, key, value)
        except Exception as e:
            with pytest.raises(type(e)):
                set_storage(state, address, key, value)
            return

        set_storage(state, address, key, value)
        assert state_cairo == state

    @given(data=state_and_address_and_optional_key())
    @settings(max_examples=100)
    def test_destroy_storage(self, cairo_run, data):
        state, address = data
        state_cairo = cairo_run("destroy_storage", state, address)
        destroy_storage(state, address)
        assert state_cairo == state


class TestTransientStorage:
    @given(data=transient_storage_and_address_and_optional_key(key_strategy=bytes32))
    def test_get_transient_storage(
        self,
        cairo_run,
        data,
    ):
        transient_storage, address, key = data
        transient_storage_cairo, result_cairo = cairo_run(
            "get_transient_storage",
            transient_storage,
            address,
            key,
        )
        assert result_cairo == get_transient_storage(transient_storage, address, key)
        assert transient_storage_cairo == transient_storage

    @given(
        data=transient_storage_and_address_and_optional_key(key_strategy=bytes32),
        value=...,
    )
    def test_set_transient_storage(
        self,
        cairo_run,
        data,
        value: U256,
    ):
        transient_storage, address, key = data
        transient_storage_cairo = cairo_run(
            "set_transient_storage",
            transient_storage,
            address,
            key,
            value,
        )
        set_transient_storage(transient_storage, address, key, value)
        assert transient_storage_cairo == transient_storage


class TestBeginTransaction:
    @given(state=..., transient_storage=...)
    def test_begin_transaction(
        self, cairo_run, state: State, transient_storage: TransientStorage
    ):
        state_cairo, transient_storage_cairo = cairo_run(
            "begin_transaction",
            state,
            transient_storage,
        )
        begin_transaction(state, transient_storage)
        assert state_cairo == state
        assert transient_storage_cairo == transient_storage

    @given(
        state=state_with_snapshots(),
        transient_storage=transient_storage_with_snapshots(),
    )
    def test_rollback_transaction(
        self, cairo_run, state: State, transient_storage: TransientStorage
    ):
        try:
            state_cairo, transient_storage_cairo = cairo_run(
                "rollback_transaction", state, transient_storage
            )
        except Exception as e:
            with strict_raises(type(e)):
                rollback_transaction(state, transient_storage)
            return
        rollback_transaction(state, transient_storage)
        assert state_cairo == state
        assert transient_storage_cairo == transient_storage

    @given(
        state=state_with_snapshots(),
        transient_storage=transient_storage_with_snapshots(),
    )
    def test_commit_transaction(
        self, cairo_run, state: State, transient_storage: TransientStorage
    ):
        try:
            state_cairo, transient_storage_cairo = cairo_run(
                "commit_transaction", state, transient_storage
            )
        except Exception as e:
            with strict_raises(type(e)):
                commit_transaction(state, transient_storage)
            return
        commit_transaction(state, transient_storage)
        assert state_cairo == state
        assert transient_storage_cairo == transient_storage

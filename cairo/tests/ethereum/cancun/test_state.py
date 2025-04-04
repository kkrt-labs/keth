import copy
from typing import Mapping, Optional

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
    state_root,
    storage_root,
    touch_account,
)
from ethereum.cancun.trie import Trie, copy_trie
from ethereum.crypto.hash import keccak256
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
    state_strategy,
    transient_storage,
    trie_strategy,
)


@composite
def state_and_address_and_optional_key(
    draw,
    state_strategy=state_strategy(),
    address_strategy=address,
    key_strategy=None,
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
    base_state = draw(state_strategy())
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
    state_strategy=state_strategy(),
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

    @given(
        data=state_and_address_and_optional_key(),
        code=st.binary(min_size=1, max_size=256),
    )
    def test_account_has_code_or_nonce_with_code_non_empty(
        self, cairo_run, data, code: bytes
    ):
        state, address = data
        account = get_account(state, address)
        codehash = keccak256(code)
        set_account(
            state,
            address,
            Account(
                balance=account.balance,
                code=code,
                nonce=account.nonce,
                storage_root=account.storage_root,
                code_hash=codehash,
            ),
        )
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
    def test_is_account_empty_high_balance(self, cairo_run, data):
        state, address = data
        set_account_balance(state, address, U256(2**128))
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


@composite
def state_maybe_snapshot(draw):
    """
    Draw a state that has a 80% chance of not containing snapshots.
    """
    state_ = draw(state_strategy())
    probability = draw(st.floats(min_value=0, max_value=1))
    if probability < 0.8:
        state_._snapshots = []
        return state_
    return state_


class TestRoot:
    @given(state=state_maybe_snapshot())
    def test_state_root(self, cairo_run, state: State):
        try:
            state_root_cairo = cairo_run("state_root", state)
        except Exception as e:
            with strict_raises(type(e)):
                state_root(state)
            return
        state_root_py = state_root(state)
        assert state_root_cairo == state_root_py


class TestStorageRoots:
    @given(state=state_maybe_snapshot())
    def test_storage_roots(self, cairo_run, state: State):
        def storage_roots(state) -> Mapping[Address, Bytes32]:
            # This assertion is made in each individual storage_root in python -
            # but in Cairo we can only perform it once.
            assert not state._snapshots
            storage_roots_py = {}
            for addr in state._storage_tries.keys():
                storage_roots_py[addr] = storage_root(state, addr)
            return storage_roots_py

        try:
            storage_roots_cairo = cairo_run("storage_roots", state)
        except Exception as e:
            with strict_raises(type(e)):
                storage_roots(state)
            return

        assert storage_roots_cairo == storage_roots(state)


class TestGetAccountCode:
    def _create_account_no_code(self, account: Account) -> Account:
        """Helper function to create a copy of an account with code set to None."""
        return Account(
            balance=account.balance,
            nonce=account.nonce,
            code=None,  # Explicitly remove code for testing retrieval
            code_hash=account.code_hash,
            storage_root=account.storage_root,
        )

    def _prepare_codehash_input(self, code_hash: Bytes32, code: bytes) -> dict:
        """Helper function to prepare the codehash_to_code input dictionary."""
        # Convert Bytes32 code_hash to the low/high u128 pair expected by Cairo
        code_hash_int = int.from_bytes(code_hash, "little")
        code_hash_low = code_hash_int & (2**128 - 1)
        code_hash_high = code_hash_int >> 128
        return {"codehash_to_code": {(code_hash_low, code_hash_high): code}}

    @given(state=..., address=..., account=...)
    def test_get_account_code_cached(
        self, cairo_run, state: State, address: Address, account: Account
    ):
        """
        Test that get_account_code returns code directly if already present in the account object.
        """
        # Set an account that already includes its code.
        set_account(state, address, account)

        # Call the Cairo function.
        state_cairo, code_cairo = cairo_run("get_account_code", state, address, account)

        # Assert: Returned code matches, state remains consistent.
        assert code_cairo == account.code
        assert get_account(state_cairo, address) == account

    @given(state=..., address=..., account=...)
    def test_get_account_code_from_input(
        self, cairo_run, state: State, address: Address, account: Account
    ):
        """
        Test that get_account_code retrieves code from the input map when not cached.
        """
        # Create an account without code and prepare input map.
        account_no_code = self._create_account_no_code(account)
        set_account(state, address, account_no_code)
        program_input = self._prepare_codehash_input(account.code_hash, account.code)

        # Call the Cairo function with the input map.
        state_cairo, code_cairo = cairo_run(
            "get_account_code",
            state,
            address,
            account_no_code,
            codehash_to_code=program_input["codehash_to_code"],
        )

        # Assert: Correct code is returned and inserted into the account in the state.
        assert code_cairo == account.code
        # Reconstruct the expected final account state after code retrieval
        expected_account = Account(
            balance=account.balance,
            nonce=account.nonce,
            code=code_cairo,  # Code should now be filled
            code_hash=account.code_hash,
            storage_root=account.storage_root,
        )
        assert get_account(state_cairo, address) == expected_account

    @given(state=..., address=..., account=...)
    def test_get_account_code_raises_on_mismatched_hash(
        self, cairo_run, state: State, address: Address, account: Account
    ):
        """
        Test that get_account_code raises an error if the provided code's hash
        doesn't match the requested code_hash.
        """
        # Arrange: Create an account without code.
        account_no_code = self._create_account_no_code(account)
        set_account(state, address, account_no_code)

        # Arrange: Prepare input map with a deliberately incorrect code (flipped last byte).
        # We manually create the input here to use the wrong code to the hash
        code_hash_int = int.from_bytes(account.code_hash, "little")
        code_hash_low = code_hash_int & (2**128 - 1)
        code_hash_high = code_hash_int >> 128
        incorrect_code = (
            account.code[:-1] + bytes([account.code[-1] ^ 1])
            if account.code != b""
            else b"wrong code"
        )
        program_input = {
            "codehash_to_code": {(code_hash_low, code_hash_high): incorrect_code}
        }

        # Expect an assertion error from the Cairo execution.
        # The Cairo function should verify keccak256(code) == account.code_hash.
        with pytest.raises(AssertionError):
            cairo_run(
                "get_account_code",
                state,
                address,
                account_no_code,
                codehash_to_code=program_input["codehash_to_code"],
            )

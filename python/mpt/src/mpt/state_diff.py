from typing import Dict, Optional

from ethereum.cancun.fork_types import Account, Address
from ethereum.cancun.state import State, get_account
from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U256


class AccountDiff:
    """
    A class that contains the differences for a single account, including its storage changes.
    If account is None, it represents a deletion.
    """

    account: Optional[Account]
    storage_updates: Dict[Bytes32, U256]

    def __init__(self, account: Optional[Account] = None):
        self.account = account
        self.storage_updates = {}


class StateDiff:
    """
    A class that contains the differences between two states.
    """

    account_diffs: Dict[Address, AccountDiff]

    def __init__(self):
        self.account_diffs: Dict[Address, AccountDiff] = {}

    @classmethod
    def from_pre_post(cls, pre_state: State, post_state: State) -> "StateDiff":
        """
        Compute a state diff between two states: a pre_state and a post_state.

        Parameters
        ----------
        pre_state : State
            The state before executing a block
        post_state : State
            The state after executing a block

        Returns
        -------
        StateDiff
            A StateDiff object containing:
            - 'account_diffs': Dict[Address, AccountDiff] - Accounts that were added, modified or deleted with their storage changes
        """
        return compute_state_diff(pre_state, post_state)


def compute_state_diff(pre_state: State, post_state: State) -> StateDiff:
    """
    Compute the difference between pre_state and post_state.

    Parameters
    ----------
    pre_state : State
        The state before executing a block
    post_state : State
        The state after executing a block

    Returns
    -------
    StateDiff
        A StateDiff object containing:
        - 'account_diffs': Dict[Address, AccountDiff] - Accounts that were added, modified or deleted with their storage changes
    """

    diff = StateDiff()

    pre_addresses = set(pre_state._main_trie._data.keys())
    post_addresses = set(post_state._main_trie._data.keys())

    # Find deleted accounts
    deletions = pre_addresses - post_addresses
    for address in deletions:
        # Process deleted account
        account_diff = compute_account_diff(pre_state, post_state, address)
        if account_diff is not None:
            diff.account_diffs[address] = account_diff

    # Find added or modified accounts
    for address in post_addresses:
        # Process added or modified account
        account_diff = compute_account_diff(pre_state, post_state, address)
        if account_diff is not None:
            diff.account_diffs[address] = account_diff

    return diff


def compute_account_diff(
    pre_state: State,
    post_state: State,
    address: Address,
) -> Optional[AccountDiff]:
    """
    Process account and storage changes.

    Parameters
    ----------
    pre_state : State
        The state before executing a block
    post_state : State
        The state after executing a block
    address : Address
        The address of the account

    Returns
    -------
    Optional[AccountDiff]
        An AccountDiff object if there were any changes, None otherwise
    """
    pre_account = (
        get_account(pre_state, address)
        if address in pre_state._main_trie._data
        else None
    )

    post_account = (
        get_account(post_state, address)
        if address in post_state._main_trie._data
        else None
    )

    # Check if account changed
    account_modified = post_account != pre_account

    # Create account diff if account was modified
    account_diff = AccountDiff(post_account) if account_modified else None

    # Check if the account has storage in either state
    has_pre_storage = address in pre_state._storage_tries
    has_post_storage = address in post_state._storage_tries

    # If no storage in either state, return account diff (if any)
    if not has_pre_storage and not has_post_storage:
        return account_diff

    # Create account diff if it doesn't exist yet but we have storage to process
    if account_diff is None:
        account_diff = AccountDiff(post_account)

    # If account is deleted or storage only in pre state, set all pre-storage to zero
    if post_account is None or (has_pre_storage and not has_post_storage):
        if has_pre_storage:
            pre_storage = pre_state._storage_tries[address]
            for key, value in pre_storage._data.items():
                if value != U256(0):  # Only record non-zero values being set to zero
                    account_diff.storage_updates[key] = U256(0)

    # If storage only in post state, add all post-storage
    elif not has_pre_storage and has_post_storage:
        post_storage = post_state._storage_tries[address]
        for key, value in post_storage._data.items():
            account_diff.storage_updates[key] = value

    # Both states have storage, compare them
    elif has_pre_storage and has_post_storage:
        pre_storage = pre_state._storage_tries[address]
        post_storage = post_state._storage_tries[address]

        all_keys = set(pre_storage._data.keys()).union(set(post_storage._data.keys()))

        for key in all_keys:
            pre_value = pre_storage._data.get(key, U256(0))
            post_value = post_storage._data.get(key, U256(0))

            if pre_value != post_value:
                account_diff.storage_updates[key] = post_value

    # Return account diff if there were any changes, None otherwise
    if account_modified or len(account_diff.storage_updates) > 0:
        return account_diff
    else:
        return None

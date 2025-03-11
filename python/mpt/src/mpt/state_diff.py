from typing import Dict, Set

from ethereum.cancun.fork_types import Account, Address
from ethereum.cancun.state import State, get_account
from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U256


class StateDiff:
    """
    A class that contains the differences between two states.
    """

    updates: Dict[Address, Account]
    deletions: Set[Address]
    storage_updates: Dict[Address, Dict[Bytes32, U256]]
    storage_deletions: Dict[Address, Set[Bytes32]]

    def __init__(self):
        self.updates = {}
        self.deletions = set()
        self.storage_updates = {}
        self.storage_deletions = {}

    @classmethod
    def from_pre_post(cls, pre_state: State, post_state: State) -> "StateDiff":
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
        - 'updates': Dict[Address, Account] - Accounts that were added or modified
        - 'deletions': Set[Address] - Accounts that were deleted
        - 'storage_updates': Dict[Address, Dict[Bytes32, U256]] - Storage slots that were added or modified
        - 'storage_deletions': Dict[Address, Set[Bytes32]] - Storage slots that were deleted
    """

    diff = StateDiff()

    pre_addresses = set(pre_state._main_trie._data.keys())
    post_addresses = set(post_state._main_trie._data.keys())

    # Find deleted accounts
    deletions = pre_addresses - post_addresses
    for address in deletions:
        process_storage_changes(pre_state, post_state, address, diff)
    diff.deletions.update(deletions)

    # Find added or modified accounts
    for address in post_addresses:
        post_account = get_account(post_state, address)
        if address not in pre_addresses:
            # New account
            if post_account is not None:
                diff.updates[address] = post_account

                # Check if the new account has storage
                if address in post_state._storage_tries:
                    process_new_account_storage(post_state, address, diff)
        else:
            # Account exists in both states, check if it was modified
            pre_account = get_account(pre_state, address)

            # If the accounts are different, add to updates
            if post_account != pre_account:
                if post_account is not None:
                    diff.updates[address] = post_account
                else:
                    # Account was set to None, add to deletions
                    diff.deletions.add(address)

            # Check for storage changes even if the account itself hasn't changed
            if post_account is not None:
                process_storage_changes(pre_state, post_state, address, diff)

    return diff


def process_new_account_storage(
    post_state: State, address: Address, diff: StateDiff
) -> None:
    """
    Process storage for a newly created account.

    Parameters
    ----------
    post_state : State
        The state after executing a block
    address : Address
        The address of the new account
    diff : StateDiff
        The diff dictionary to update
    """
    if address not in post_state._storage_tries:
        return

    storage_trie = post_state._storage_tries[address]

    # Add all non-zero storage values
    for key, value in storage_trie._data.items():
        if value != U256(0):
            if address not in diff.storage_updates:
                diff.storage_updates[address] = {}
            diff.storage_updates[address][key] = value


def process_storage_changes(
    pre_state: State, post_state: State, address: Address, diff: StateDiff
):
    """
    Process storage changes for an account that exists in both pre and post states.

    Parameters
    ----------
    pre_state : State
        The state before executing a block
    post_state : State
        The state after executing a block
    address : Address
        The address of the account
    diff : StateDiff
        The diff dictionary to update
    """
    # Check if the account has storage in either state
    has_pre_storage = address in pre_state._storage_tries
    has_post_storage = address in post_state._storage_tries

    # If no storage in either state, nothing to do
    if not has_pre_storage and not has_post_storage:
        return

    # If storage only in post state, all are additions
    if not has_pre_storage and has_post_storage:
        process_new_account_storage(post_state, address, diff)
        return

    # If storage only in pre state, all are deletions
    if has_pre_storage and not has_post_storage:
        pre_storage = pre_state._storage_tries[address]
        if address not in diff.storage_deletions:
            diff.storage_deletions[address] = set()

        for key in pre_storage._data.keys():
            diff.storage_deletions[address].add(key)
        return

    # Both states have storage, compare them
    pre_storage = pre_state._storage_tries[address]
    post_storage = post_state._storage_tries[address]

    pre_keys = set(pre_storage._data.keys())
    post_keys = set(post_storage._data.keys())

    # Find deleted storage slots
    deleted_keys = pre_keys - post_keys
    if deleted_keys:
        if address not in diff.storage_deletions:
            diff.storage_deletions[address] = set()
        diff.storage_deletions[address].update(deleted_keys)

    # Find added or modified storage slots
    for key in post_keys:
        post_value = post_storage._data[key]

        # Skip zero values (they're considered deleted)
        if post_value == U256(0):
            if key in pre_keys and pre_storage._data[key] != 0:
                # Value changed from non-zero to zero, mark as deletion
                if address not in diff.storage_deletions:
                    diff.storage_deletions[address] = set()
                diff.storage_deletions[address].add(key)
            continue

        # Check if key is new or value changed
        if key not in pre_keys or pre_storage._data[key] != post_value:
            if address not in diff.storage_updates:
                diff.storage_updates[address] = {}
            diff.storage_updates[address][key] = post_value

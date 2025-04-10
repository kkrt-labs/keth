from typing import Any, Dict, List, Optional

from ethereum.cancun.trie import root
from ethereum.crypto.hash import keccak256
from ethereum.utils.hexadecimal import (
    hex_to_bytes,
    hex_to_bytes32,
    hex_to_hash,
    hex_to_uint,
)
from ethereum_spec_tools.evm_tools.loaders.fixture_loader import Load
from ethereum_types.numeric import U256

from mpt.ethereum_tries import EMPTY_TRIE_HASH
from tests.utils.args_gen import EMPTY_ACCOUNT


class LoadKethFixture(Load):
    """
    A superclass of the `Load` class that loads EELS-format fixtures for Keth
    """

    def json_to_state(
        self, raw_state: Dict[str, Any], post_state_keys: Optional[List[str]] = []
    ) -> Any:
        """
        Converts json state data to a state object.

        Args:
            raw_state: Dictionary containing the raw state data for accounts, where keys are
                      hex-encoded addresses and values are account state dictionaries
            post_state_keys: Optional list of addresses that are part of the state after executing the STF against the Raw state. Used to ensure all
                       accounts that will be touched during transaction execution are present
                       in the initial state. Defaults to empty list.

        Note:
            - This function loads and computes both code hashes and storage roots from the input json
            - We use both raw_state and post_state_keys to ensure all accounts touched in the transaction
              are present in the initial state, even if they start as empty accounts. In our Cairo
              execution flow, for soundness purposes, all accounts must be present in the initial
              state dict, even if empty.
            - For EELS inputs (unlike ZKPI inputs):
                * If storage_root is not provided, it's computed from the account's storage (as this is not a partial storage)
                * If code_hash is not provided, it's computed from the account's code

        Returns:
            State: A State object initialized with all accounts required in the pre-state.
        """
        state = self.fork.State()
        set_storage = self.fork.set_storage

        all_accounts_touched = set(raw_state.keys()) | set(post_state_keys)

        for address_hex in all_accounts_touched:
            address = self.fork.hex_to_address(address_hex)
            account_state = raw_state.get(address_hex, {})

            # Create an entry for an EMPTY_ACCOUNT to ensure that the account exists in state.
            self.fork.set_account(state, address, EMPTY_ACCOUNT)

            # Set storage to compute storage root of account
            for k, v in account_state.get("storage", {}).items():
                set_storage(
                    state,
                    address,
                    hex_to_bytes32(k),
                    U256.from_be_bytes(hex_to_bytes32(v)),
                )

            # If the storage root is not provided, compute it from the account's storage.
            # This only happens for EELS inputs; not ZKPI inputs.
            if not account_state.get("storage_root"):
                if address in state._storage_tries:
                    storage_root = root(state._storage_tries[address])
                else:
                    storage_root = EMPTY_TRIE_HASH
            else:
                storage_root = hex_to_hash(account_state.get("storage_root"))

            # If the code hash is not provided, compute it from the account's code.
            # This only happens for EELS inputs; not ZKPI inputs.
            if not account_state.get("code_hash"):
                code_hash = keccak256(hex_to_bytes(account_state.get("code", "")))
            else:
                code_hash = hex_to_hash(account_state.get("code_hash"))

            account = self.fork.Account(
                nonce=hex_to_uint(account_state.get("nonce", "0x0")),
                balance=U256(hex_to_uint(account_state.get("balance", "0x0"))),
                code=hex_to_bytes(account_state.get("code", "")),
                storage_root=storage_root,
                code_hash=code_hash,
            )
            self.fork.set_account(state, address, account)

        return state

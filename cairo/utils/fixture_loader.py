from collections import defaultdict
from typing import Any, Dict

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

    def json_to_state(self, raw: Dict[str, Any]) -> Any:
        """
        Converts json state data to a state object.

        Args:
            raw: Dictionary containing the raw state data for accounts, where keys are
                hex-encoded addresses and values are account state dictionaries
        Note:
            - This function loads and computes both code hashes and storage roots from the input json
            - Not all accounts touched during a transaction are present in the input json. As such, we made the State tries `defaultdict`, so that the
                execution would not fail in case of missing accounts. However, in the e2e proving flow, these tries are not defaultdict - and when we finalize them,
                we don't check that it's consistent with the default value.
            - For EELS inputs (unlike ZKPI inputs):
                * If storage_root is not provided, it's computed from the account's storage (as this is not a partial storage)
                * If code_hash is not provided, it's computed from the account's code

        Returns:
            State: A State object initialized with all accounts required in the pre-state.
        """
        state = self.fork.State()
        # Explicitly set the main trie as a defaultdict
        state._main_trie._data = defaultdict(lambda: None, {})

        set_storage = self.fork.set_storage

        for address_hex, account_state in raw.items():
            address = self.fork.hex_to_address(address_hex)

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

            # Explicitly set the storage trie as a defaultdict
            if address in state._storage_tries:
                state._storage_tries[address]._data = defaultdict(
                    lambda: U256(0), state._storage_tries[address]._data
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

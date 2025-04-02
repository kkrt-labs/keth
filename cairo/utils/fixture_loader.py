from typing import Any

from ethereum.utils.hexadecimal import (
    hex_to_bytes,
    hex_to_bytes8,
    hex_to_bytes32,
    hex_to_hash,
    hex_to_u64,
    hex_to_u256,
    hex_to_uint,
)
from ethereum_spec_tools.evm_tools.loaders.fixture_loader import Load
from ethereum_spec_tools.evm_tools.loaders.fork_loader import ForkLoad
from ethereum_types.numeric import U256


class LoadKethFixture(Load):
    """
    A superclass of the `Load` class that loads EELS-format fixtures for Keth
    """

    def json_to_state(self, raw: Any) -> Any:
        """
        Converts json state data to a state object
        Note: this function also loads the code hashes and storage roots from the input json
        """
        state = self.fork.State()
        set_storage = self.fork.set_storage

        for address_hex, account_state in raw.items():
            address = self.fork.hex_to_address(address_hex)
            account = self.fork.Account(
                nonce=hex_to_uint(account_state.get("nonce", "0x0")),
                balance=U256(hex_to_uint(account_state.get("balance", "0x0"))),
                code=hex_to_bytes(account_state.get("code", "")),
                storage_root=hex_to_hash(account_state.get("storage_root", "")),
                code_hash=hex_to_hash(account_state.get("code_hash", "")),
            )
            self.fork.set_account(state, address, account)

            for k, v in account_state.get("storage", {}).items():
                set_storage(
                    state,
                    address,
                    hex_to_bytes32(k),
                    U256.from_be_bytes(hex_to_bytes32(v)),
                )
        return state

import json
import logging
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Tuple, Union

from ethereum.cancun.blocks import Block, Withdrawal
from ethereum.cancun.fork import (
    BlockChain,
)
from ethereum.cancun.fork_types import EMPTY_ACCOUNT, Address
from ethereum.cancun.state import State
from ethereum.cancun.transactions import (
    LegacyTransaction,
    encode_transaction,
)
from ethereum.cancun.trie import Trie, root, trie_get
from ethereum.crypto.hash import keccak256
from ethereum.utils.hexadecimal import (
    hex_to_bytes,
    hex_to_bytes32,
    hex_to_hash,
    hex_to_u256,
    hex_to_uint,
)
from ethereum_spec_tools.evm_tools.loaders.fixture_loader import Load
from ethereum_spec_tools.evm_tools.loaders.fork_loader import ForkLoad
from ethereum_spec_tools.evm_tools.loaders.transaction_loader import TransactionLoad
from ethereum_types.bytes import Bytes, Bytes0
from ethereum_types.numeric import U64, U256

from keth_types.types import EMPTY_BYTES_HASH, EMPTY_TRIE_HASH
from mpt.ethereum_tries import ZkPi

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

CANCUN_FORK_BLOCK = 19426587  # First Cancun block


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
                execution would not fail in case of missing accounts. However, in the e2e proving flow, these tries are not defaultdict - and when we finalize (`finalize_state`) them,
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
        # Explicitly set the storage tries as a defaultdict
        state._storage_tries = defaultdict(
            lambda: Trie(
                secured=True,
                default=U256(0),
                _data=defaultdict(lambda: U256(0), {}),
            ),
        )
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


def map_code_hashes_to_code(
    state: State,
) -> Tuple[State, Dict[Tuple[int, int], Bytes]]:
    code_hashes = {}

    for address in state._main_trie._data:
        account = trie_get(state._main_trie, address)
        if not account:
            account_code_hash = EMPTY_BYTES_HASH
            account_code = b""
        else:
            account_code_hash = account.code_hash
            account_code = account.code
        code_hash_int = int.from_bytes(account_code_hash, "little")
        code_hash_low = code_hash_int & 2**128 - 1
        code_hash_high = code_hash_int >> 128
        code_hashes[(code_hash_low, code_hash_high)] = account_code

    return code_hashes


def load_zkpi_fixture(zkpi_path: Union[Path, str]) -> Dict[str, Any]:
    """
    Load and convert ZKPI fixture to Keth-compatible public inputs.

    Args:
        zkpi_path: Path to the ZKPI JSON file

    Returns:
        Dictionary of public inputs

    Raises:
        FileNotFoundError: If the ZKPI file doesn't exist
        ValueError: If JSON is invalid or data conversion fails
    """
    try:
        with open(zkpi_path, "r") as f:
            prover_inputs = json.load(f)
    except Exception as e:
        logger.error(f"Error loading ZKPI file from {zkpi_path}: {e}")
        raise e

    load = LoadKethFixture("Cancun", "cancun")
    if len(prover_inputs["blocks"]) > 1:
        raise ValueError("Only one block is supported")
    input_block = prover_inputs["blocks"][0]
    block_transactions = input_block["transaction"]
    transactions = process_block_transactions(block_transactions)

    # Convert block
    block = Block(
        header=load.json_to_header(input_block["header"]),
        transactions=transactions,
        ommers=(),
        withdrawals=tuple(
            Withdrawal(
                index=U64(int(w["index"], 16)),
                validator_index=U64(int(w["validatorIndex"], 16)),
                address=Address(hex_to_bytes(w["address"])),
                amount=U256(int(w["amount"], 16)),
            )
            for w in input_block["withdrawals"]
        ),
    )

    # Convert ancestors
    blocks = [
        Block(
            header=load.json_to_header(ancestor),
            transactions=(),
            ommers=(),
            withdrawals=(),
        )
        for ancestor in prover_inputs["witness"]["ancestors"][::-1]
    ]

    zkpi = ZkPi.from_data(prover_inputs)
    transition_db = zkpi.transition_db
    pre_state = zkpi.pre_state

    # Create blockchain
    code_hashes = map_code_hashes_to_code(pre_state)
    chain = BlockChain(
        blocks=blocks,
        state=pre_state,
        chain_id=U64(prover_inputs["chainConfig"]["chainId"]),
    )

    # Prepare inputs
    program_input = {
        "block": block,
        "blockchain": chain,
        "codehash_to_code": code_hashes,
        "node_store": transition_db.nodes,
        "address_preimages": transition_db.address_preimages,
        "storage_key_preimages": transition_db.storage_key_preimages,
        "post_state_root": transition_db.post_state_root,
    }

    return program_input


def normalize_transaction(tx: Dict[str, Any]) -> Dict[str, Any]:
    """
    Normalize transaction fields to match what TransactionLoad expects.
    """
    tx = tx.copy()
    tx["gasLimit"] = tx.pop("gas")
    tx["data"] = tx.pop("input")
    tx["to"] = tx["to"] if tx["to"] is not None else ""
    return tx


def process_block_transactions(
    block_transactions: List[Dict[str, Any]],
) -> Tuple[Tuple[LegacyTransaction, ...], Tuple[Dict[str, Any], ...]]:

    transactions = tuple(
        TransactionLoad(normalize_transaction(tx), ForkLoad("cancun")).read()
        for tx in block_transactions
    )
    encoded_transactions = tuple(
        (
            "0x" + encode_transaction(tx).hex()
            if not isinstance(tx, LegacyTransaction)
            else {
                "nonce": hex(tx.nonce),
                "gasPrice": hex(tx.gas_price),
                "gas": hex(tx.gas),
                "to": "0x" + tx.to.hex() if tx.to else "",
                "value": hex(tx.value),
                "data": "0x" + tx.data.hex(),
                "v": hex(tx.v),
                "r": hex(tx.r),
                "s": hex(tx.s),
            }
        )
        for tx in transactions
    )
    transactions = tuple(
        (
            LegacyTransaction(
                nonce=hex_to_u256(tx["nonce"]),
                gas_price=hex_to_uint(tx["gasPrice"]),
                gas=hex_to_uint(tx["gas"]),
                to=Address(hex_to_bytes(tx["to"])) if tx["to"] else Bytes0(),
                value=hex_to_u256(tx["value"]),
                data=Bytes(hex_to_bytes(tx["data"])),
                v=hex_to_u256(tx["v"]),
                r=hex_to_u256(tx["r"]),
                s=hex_to_u256(tx["s"]),
            )
            if isinstance(tx, dict)
            else Bytes(hex_to_bytes(tx))
        )
        for tx in encoded_transactions
    )

    return transactions

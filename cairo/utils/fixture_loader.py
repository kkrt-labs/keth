import copy
import json
import logging
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, Union

from ethereum.crypto.hash import keccak256
from ethereum.prague.blocks import Block, Log, Receipt, Withdrawal
from ethereum.prague.fork import (
    BEACON_ROOTS_ADDRESS,
    BlockChain,
    get_last_256_block_hashes,
    process_system_transaction,
    process_transaction,
)
from ethereum.prague.fork_types import (
    EMPTY_ACCOUNT,
    Account,
    Address,
)
from ethereum.prague.state import (
    State,
    TransientStorage,
)
from ethereum.prague.transactions import (
    LegacyTransaction,
    decode_transaction,
    encode_transaction,
)
from ethereum.prague.trie import Trie, copy_trie, root, trie_get
from ethereum.prague.vm import (
    BlockEnvironment,
    BlockOutput,
)
from ethereum.prague.vm.gas import (
    calculate_excess_blob_gas,
)
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
from ethereum_types.numeric import U64, U256, Uint

from keth_types.types import EMPTY_BYTES_HASH, EMPTY_TRIE_HASH
from mpt.ethereum_tries import ZkPi

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

PRAGUE_FORK_BLOCK = 22431084  # First Prague block


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

    load = LoadKethFixture("prague", "prague")
    if len(prover_inputs["blocks"]) > 1:
        raise ValueError("Only one block is supported")

    # TODO(zkpi): Remove requestsHash key if null from block header and all ancestors
    input_block = prover_inputs["blocks"][0]
    if (
        "requestsHash" in input_block["header"]
        and input_block["header"]["requestsHash"] is None
    ):
        del input_block["header"]["requestsHash"]

    # Also remove from ancestors
    for ancestor in prover_inputs["witness"]["ancestors"]:
        if "requestsHash" in ancestor and ancestor["requestsHash"] is None:
            del ancestor["requestsHash"]

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


def zkpi_fixture_eels_compatible(zkpi_path: Union[Path, str]) -> Dict[str, Any]:
    """
    Load and convert ZKPI fixture to EELS-compatible public inputs.
    """
    zkpi_program_input = load_zkpi_fixture(zkpi_path=zkpi_path)

    blockchain = zkpi_program_input["blockchain"]
    format_state_for_eels(blockchain.state)
    return zkpi_program_input


def format_state_for_eels(state: State) -> State:
    """
    Format the state to run with EELS.
    """
    # EELS expects "None" accounts to not be in the state.
    accounts_to_delete = [
        address
        for address, account in state._main_trie._data.items()
        if account is None
    ]
    for address in accounts_to_delete:
        del state._main_trie._data[address]

    # EELS expects code of accounts without code to be an empty bytearray.
    for address, account in state._main_trie._data.items():
        if account and not account.code:
            state._main_trie._data[address] = Account(
                nonce=account.nonce,
                balance=account.balance,
                code_hash=account.code_hash,
                storage_root=account.storage_root,
                code=b"",
            )

    for address in state._storage_tries:
        # EELS expects empty storage values to be deleted.
        # If a trie has no remaining value, then it's entirely deleted.
        storage_trie = state._storage_tries[address]
        keys_to_delete = [k for k, v in storage_trie._data.items() if v is None]
        for key in keys_to_delete:
            del storage_trie._data[key]

    tries_to_delete = [
        address
        for address in state._storage_tries
        if not state._storage_tries[address]._data
    ]
    for address in tries_to_delete:
        del state._storage_tries[address]

    return


def transient_storage_for_eels() -> TransientStorage:
    """
    Format the transient storage to run with EELS.
    """
    return TransientStorage(_data=defaultdict(lambda: None, {}), _snapshots=[])


def prepare_body_input(
    block_env: BlockEnvironment,
    transactions: Tuple[Union[LegacyTransaction, Bytes], ...],
) -> Dict[str, Any]:
    """
    Prepare the input for the body step.
    Runs the STF on the subset of transactions passed as argument.
    Outputs the state post-transactions (new state, remaining gas, etc.)
    """
    transactions_trie: Trie[Bytes, Optional[Union[Bytes, LegacyTransaction]]] = Trie(
        secured=False, default=None, _data=defaultdict(lambda: None)
    )
    receipts_trie: Trie[Bytes, Optional[Union[Bytes, Receipt]]] = Trie(
        secured=False, default=None, _data=defaultdict(lambda: None)
    )
    withdrawals_trie: Trie[Bytes, Optional[Union[Bytes, Withdrawal]]] = Trie(
        secured=False, default=None, _data=defaultdict(lambda: None)
    )
    block_logs: Tuple[Log, ...] = ()

    block_output = BlockOutput(
        block_gas_used=Uint(0),
        transactions_trie=transactions_trie,
        receipts_trie=receipts_trie,
        receipt_keys=[],
        block_logs=block_logs,
        withdrawals_trie=withdrawals_trie,
        blob_gas_used=U64(0),
    )

    format_state_for_eels(block_env.state)

    process_system_transaction(
        block_env=block_env,
        target_address=BEACON_ROOTS_ADDRESS,
        data=block_env.parent_beacon_block_root,
    )

    for i, tx in enumerate(map(decode_transaction, transactions)):
        process_transaction(block_env, block_output, tx, Uint(i))

    # process_withdrawals(block_env, block_output, withdrawals)

    # Cairo expects code of accounts to be initially None, as they're lazily loaded
    # during execution.
    state = block_env.state
    for address, account in state._main_trie._data.items():
        if account and account.code_hash == EMPTY_BYTES_HASH:
            state._main_trie._data[address] = Account(
                nonce=account.nonce,
                balance=account.balance,
                code_hash=account.code_hash,
                storage_root=account.storage_root,
                code=None,
            )

    for address, storage_trie in state._storage_tries.items():
        for storage_key, storage_value in storage_trie._data.items():
            if storage_value == U256(0):
                storage_trie._data[storage_key] = None

    return {
        "block_env": block_env,
        "block_output": block_output,
    }


def load_body_input(
    zkpi_path: Union[Path, str], start_index: int, chunk_size: int
) -> Dict[str, Any]:
    """
    Load and convert ZKPI fixture to Keth-compatible public inputs for the body step.
    Advances the state by the number of transactions specified by `start_index` and `chunk_size`.
    """
    zkpi_program_input = load_zkpi_fixture(zkpi_path=zkpi_path)
    chain = zkpi_program_input["blockchain"]
    block = zkpi_program_input["block"]
    parent_header = chain.blocks[-1].header
    excess_blob_gas = calculate_excess_blob_gas(parent_header)

    # We need to save the pre-state of the state to be able to inject it as original snapshot
    main_trie_snapshot = copy_trie(chain.state._main_trie)
    storage_tries_snapshot = copy.deepcopy(chain.state._storage_tries)

    block_env = BlockEnvironment(
        chain_id=chain.chain_id,
        state=chain.state,
        block_gas_limit=block.header.gas_limit,
        block_hashes=get_last_256_block_hashes(chain),
        coinbase=block.header.coinbase,
        number=block.header.number,
        base_fee_per_gas=block.header.base_fee_per_gas,
        time=block.header.timestamp,
        prev_randao=block.header.prev_randao,
        excess_blob_gas=excess_blob_gas,
        parent_beacon_block_root=block.header.parent_beacon_block_root,
    )

    transactions = block.transactions[:start_index]

    body_input = prepare_body_input(
        block_env,
        transactions,
    )
    # One thing to keep in mind here is that running EELS will delete any value from the account /
    # storage trie that's set to the default value (EMPTY_ACCOUNT / U256(0)).  This means that we
    # must _manually_ put back an entry for each value that was deleted from the tries.
    updated_state = body_input["block_env"].state
    for address, account in main_trie_snapshot._data.items():
        if address not in updated_state._main_trie._data:
            updated_state._main_trie._data[address] = None

        if address not in updated_state._storage_tries:
            updated_state._storage_tries[address] = Trie(
                secured=True, default=U256(0), _data={}
            )

    for address in storage_tries_snapshot:
        for storage_key, storage_value in storage_tries_snapshot[address]._data.items():
            if storage_key not in updated_state._storage_tries[address]._data:
                updated_state._storage_tries[address]._data[storage_key] = None
    # Inject the original state as the first snapshot
    body_input["block_env"].state._snapshots = [
        (
            main_trie_snapshot,
            storage_tries_snapshot,
        )
    ]
    code_hashes = map_code_hashes_to_code(body_input["block_env"].state)
    program_input = {
        **body_input,
        "codehash_to_code": code_hashes,
        "block_header": block.header,
        "block_transactions": block.transactions,
        "start_index": start_index,
        "len": min(chunk_size, len(block.transactions) - start_index),
    }
    return program_input


def load_teardown_input(zkpi_path: Union[Path, str]) -> Dict[str, Any]:
    """
    Load and convert ZKPI fixture to Keth-compatible public inputs for the teardown step.
    Because we need the state input of the cairo program to be filled in memory with (key, prev_value, new_value) tuples,
    we format the state object so that there's one single snapshot object, corresponding to the initial state of the block.
    """
    zkpi_program_input = load_zkpi_fixture(zkpi_path=zkpi_path)
    chain = zkpi_program_input["blockchain"]
    block = zkpi_program_input["block"]
    withdrawals_trie: Trie[Bytes, Optional[Union[Bytes, Withdrawal]]] = Trie(
        secured=False, default=None, _data=defaultdict(lambda: None)
    )
    main_trie_snapshot = copy_trie(chain.state._main_trie)
    storage_tries_snapshot = copy.deepcopy(chain.state._storage_tries)

    parent_header = chain.blocks[-1].header
    excess_blob_gas = calculate_excess_blob_gas(parent_header)

    block_env = BlockEnvironment(
        chain_id=chain.chain_id,
        state=chain.state,
        block_gas_limit=block.header.gas_limit,
        block_hashes=get_last_256_block_hashes(chain),
        coinbase=block.header.coinbase,
        number=block.header.number,
        base_fee_per_gas=block.header.base_fee_per_gas,
        time=block.header.timestamp,
        prev_randao=block.header.prev_randao,
        excess_blob_gas=excess_blob_gas,
        parent_beacon_block_root=block.header.parent_beacon_block_root,
    )

    body_input = prepare_body_input(
        block_env,
        block.transactions,
    )

    if body_input["block_output"].block_gas_used != block.header.gas_used:
        raise ValueError(
            f"Block gas used mismatch: {body_input['block_output'].block_gas_used} != {block.header.gas_used}"
        )

    # One thing to keep in mind here is that running EELS will delete any value from the account /
    # storage trie that's set to the default value (EMPTY_ACCOUNT / U256(0)).  This means that we
    # must _manually_ put back an entry for each value that was deleted from the tries.
    updated_state = body_input["block_env"].state
    for address in main_trie_snapshot._data.keys():
        if address not in updated_state._main_trie._data:
            updated_state._main_trie._data[address] = None

        if address not in updated_state._storage_tries:
            updated_state._storage_tries[address] = Trie(
                secured=True, default=U256(0), _data={}
            )

    for address in storage_tries_snapshot:
        for storage_key in storage_tries_snapshot[address]._data.keys():
            if storage_key not in updated_state._storage_tries[address]._data:
                updated_state._storage_tries[address]._data[storage_key] = None

    body_input["block_env"].state = updated_state
    body_input["block_env"].state._snapshots = [
        (
            main_trie_snapshot,
            storage_tries_snapshot,
        )
    ]

    program_input = {
        # Glue with init.cairo
        **zkpi_program_input,
        "withdrawals_trie": withdrawals_trie,
        # Glue with body.cairo
        **body_input,
        "block_transactions": block.transactions,
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
        TransactionLoad(normalize_transaction(tx), ForkLoad("Prague")).read()
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

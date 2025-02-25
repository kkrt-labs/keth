"""
This script converts zkpi preflight JSON files to JSON that can be loaded
to test state transition with real L1 data. It can process a single file
or all JSON files in the zkpi directory.
"""

import json
import logging
import sys
from pathlib import Path
from typing import Any, Dict

from ethereum.cancun.transactions import LegacyTransaction, encode_transaction
from ethereum.crypto.hash import keccak256
from ethereum.utils.hexadecimal import hex_to_bytes
from ethereum_spec_tools.evm_tools.loaders.fork_loader import ForkLoad
from ethereum_spec_tools.evm_tools.loaders.transaction_loader import TransactionLoad

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler()],
)
logger = logging.getLogger(__name__)


def convert_accounts(
    zkpi_data: Dict[str, Any], code_hashes: Dict[str, str]
) -> Dict[str, Any]:
    """
    Convert ZKPI accounts to the format expected by json_to_state.
    Uses preStateProofs to reconstruct account states, and maps codeHashes to their codes.

    Parameters
    ----------
    zkpi_data : Dict[str, Any]
        The ZKPI data containing preStateProofs and storage proofs
    code_hash_to_code : Dict[str, str]
        Mapping from code hash to code

    Returns
    -------
    Dict[str, Any]
        Account data in the format expected by json_to_state
    """
    EMPTY_STORAGE_ROOT = (
        "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
    )
    state = {}

    for account_proof in zkpi_data["preStateProofs"]:
        account_state = {
            "balance": account_proof["balance"],
            "nonce": hex(account_proof.get("nonce", 0)),
            "code": code_hashes.get(account_proof["codeHash"], "0x"),
            "storage": {},
        }

        if account_proof["storageHash"] != EMPTY_STORAGE_ROOT:
            for storage_proof in account_proof.get("storageProof", []):
                key = storage_proof["key"]
                value = storage_proof["value"]
                account_state["storage"][key] = value

        state[account_proof["address"]] = account_state

    return state


def normalize_transaction(tx: Dict[str, Any]) -> Dict[str, Any]:
    """
    Normalize transaction fields to match what TransactionLoad expects.

    Parameters
    ----------
    tx : Dict[str, Any]
        Raw transaction from ZKPI

    Returns
    -------
    Dict[str, Any]
        Transaction with normalized field names
    """
    tx["gasLimit"] = tx.pop("gas")
    tx["data"] = tx.pop("input")
    return tx


def create_eels_block_parameters(block: Any) -> Dict[str, Any]:
    """
    Create a JSON structure that can be used to initialize a Cancun.Block
    class object.
    """
    transactions = tuple(
        TransactionLoad(normalize_transaction(tx), ForkLoad("cancun")).read()
        for tx in block["transactions"]
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

    return {
        "blockHeader": {
            "parentHash": block["parentHash"],
            "uncleHash": block["sha3Uncles"],
            "coinbase": block["miner"],
            "stateRoot": block["stateRoot"],
            "transactionsRoot": block["transactionsRoot"],
            "receiptsRoot": block["receiptsRoot"],
            "bloom": block["logsBloom"],
            "difficulty": block["difficulty"],
            "number": block["number"],
            "gasLimit": block["gasLimit"],
            "gasUsed": block["gasUsed"],
            "timestamp": block["timestamp"],
            "extraData": block["extraData"],
            "mixHash": block["mixHash"],
            "nonce": block["nonce"],
            "baseFeePerGas": block["baseFeePerGas"],
            "withdrawalsRoot": block["withdrawalsRoot"],
            "blobGasUsed": block["blobGasUsed"],
            "excessBlobGas": block["excessBlobGas"],
            "parentBeaconBlockRoot": block["parentBeaconBlockRoot"],
        },
        "transactions": encoded_transactions,
        "withdrawals": block.get("withdrawals", []),
    }


def process_zkpi_file(zkpi_file: Path) -> None:
    """
    Process a single ZKPI file and convert it to EELS format.

    Parameters
    ----------
    zkpi_file : Path
        Path to the ZKPI JSON file to process
    script_dir : Path
        Path to the script directory
    """
    logger.info(f"Processing {zkpi_file.name}...")

    with open(str(zkpi_file), "r") as f:
        zkpi_data = json.load(f)

    code_hashes = {
        "0x" + keccak256(hex_to_bytes(code)).hex(): code for code in zkpi_data["codes"]
    }

    fixture = {
        "newBlockParameters": create_eels_block_parameters(zkpi_data["block"]),
        "pre": convert_accounts(zkpi_data, code_hashes),
        "chainId": zkpi_data["chainConfig"].get("chainId", 1),
        "ancestors": zkpi_data["ancestors"],
    }

    output_file = zkpi_file.parents[1] / "eels" / zkpi_file.name
    output_file.parent.mkdir(parents=True, exist_ok=True)

    with open(output_file, "w") as f:
        json.dump(fixture, f, indent=2)

    logger.info(f"Created EELS fixture at {output_file}")


def main():
    if len(sys.argv) != 2:
        raise ValueError("Usage: python zkpi_to_eels_json.py <zkpi_file_or_dir>")

    path = Path(sys.argv[1])

    if path.is_file():
        process_zkpi_file(path)
    elif path.is_dir():
        zkpi_files = list(path.glob("**/*.json"))
        if not zkpi_files:
            logger.error(f"No zkpi files found in {path}")
        else:
            logger.info(f"Processing {len(zkpi_files)} zkpi files in {path}...")
            for zkpi_file in zkpi_files:
                process_zkpi_file(zkpi_file)
    else:
        raise ValueError(f"Path {path} does not exist")


if __name__ == "__main__":
    main()

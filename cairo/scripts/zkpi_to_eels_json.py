"""
This script converts zkpi preflight JSON files to JSON that can be loaded
to test state transition with real L1 data. It can process a single file
or all JSON files in the zkpi directory.
"""

import json
import sys
from pathlib import Path
from typing import Any, Dict, Optional

from ethereum.cancun.blocks import Withdrawal
from ethereum.cancun.fork import (
    ApplyBodyOutput,
    Block,
    BlockChain,
    apply_body,
    get_last_256_block_hashes,
    validate_header,
)
from ethereum.cancun.fork_types import Address, Root
from ethereum.cancun.state import state_root
from ethereum.cancun.transactions import LegacyTransaction, encode_transaction
from ethereum.cancun.vm.gas import calculate_excess_blob_gas
from ethereum.crypto.hash import keccak256
from ethereum.exceptions import InvalidBlock
from ethereum.utils.hexadecimal import hex_to_bytes, hex_to_u256, hex_to_uint
from ethereum_rlp import rlp
from ethereum_spec_tools.evm_tools.loaders.fixture_loader import Load
from ethereum_spec_tools.evm_tools.loaders.fork_loader import ForkLoad
from ethereum_spec_tools.evm_tools.loaders.transaction_loader import TransactionLoad
from ethereum_types.bytes import Bytes, Bytes0
from ethereum_types.numeric import U64, U256


def load_zkpi_json(file_path: str) -> Dict[str, Any]:
    """
    Load and parse a ZKPI JSON file.

    Parameters
    ----------
    file_path : str
        Path to the ZKPI JSON file

    Returns
    -------
    Dict[str, Any]
        Parsed JSON data
    """
    with open(file_path, "r") as f:
        return json.load(f)


def create_code_hash_to_code_map(zkpi_data: Dict[str, Any]) -> Dict[str, str]:
    """
    Create a map of code hashes to code from the ZKPI data.
    First hashes all codes in the "codes" array to create a reverse mapping.

    Parameters
    ----------
    zkpi_data : Dict[str, Any]
        The ZKPI data containing a "codes" array

    Returns
    -------
    Dict[str, str]
        Mapping from code hash (hex string) to code (hex string)
    """
    code_hash_to_code = {}

    # First create mapping from all codes in the codes array
    for code in zkpi_data["codes"]:
        # Convert hex string to bytes, hash it, and convert hash back to hex string
        code_bytes = hex_to_bytes(code)
        code_hash = "0x" + keccak256(code_bytes).hex()
        code_hash_to_code[code_hash] = code

    return code_hash_to_code


def convert_accounts(
    zkpi_data: Dict[str, Any],
    code_hash_to_code: Dict[str, str],
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

    # Process each account in preStateProofs
    for account_proof in zkpi_data["preStateProofs"]:
        address = account_proof["address"]

        # Get the code using codeHash
        code_hash = account_proof["codeHash"]
        code = code_hash_to_code.get(code_hash, "0x")

        # Initialize account state
        account_state = {
            "balance": account_proof["balance"],
            "nonce": hex(account_proof.get("nonce", 0)),
            "code": code,
            "storage": {},
        }

        # Process storage if it's not empty
        if account_proof["storageHash"] != EMPTY_STORAGE_ROOT:
            # Find storage proofs for this account
            for storage_proof in account_proof.get("storageProof", []):
                key = storage_proof["key"]
                value = storage_proof["value"]
                account_state["storage"][key] = value

        state[address] = account_state

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


def create_eels_block_parameters(
    block: Any, override_state_root: Optional[Root] = None
) -> Dict[str, Any]:
    """
    Create a JSON structure that can be used to initialize a Cancun.Block
    class object.
    """
    # Normalize transaction fields before loading
    transactions = tuple(
        TransactionLoad(normalize_transaction(tx), ForkLoad("cancun")).read()
        for tx in block["transactions"]
    )
    # Encode transactions and convert to hex strings
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


def _state_transition(chain: BlockChain, block: Block) -> ApplyBodyOutput:
    parent_header = chain.blocks[-1].header
    excess_blob_gas = calculate_excess_blob_gas(parent_header)
    if block.header.excess_blob_gas != excess_blob_gas:
        raise InvalidBlock

    validate_header(block.header, parent_header)
    if block.ommers != ():
        raise InvalidBlock
    apply_body_output = apply_body(
        chain.state,
        get_last_256_block_hashes(chain),
        block.header.coinbase,
        block.header.number,
        block.header.base_fee_per_gas,
        block.header.gas_limit,
        block.header.timestamp,
        block.header.prev_randao,
        block.transactions,
        chain.chain_id,
        block.withdrawals,
        block.header.parent_beacon_block_root,
        excess_blob_gas,
    )
    return apply_body_output


def process_zkpi_file(zkpi_file: Path, script_dir: Path) -> None:
    """
    Process a single ZKPI file and convert it to EELS format.

    Parameters
    ----------
    zkpi_file : Path
        Path to the ZKPI JSON file to process
    script_dir : Path
        Path to the script directory
    """
    print(f"Processing {zkpi_file.name}...")

    # Load the ZKPI JSON
    zkpi_data = load_zkpi_json(str(zkpi_file))

    # Create code hash to code mapping
    codes_mapping = create_code_hash_to_code_map(zkpi_data)

    # Convert accounts using the code mapping
    pre_state = convert_accounts(zkpi_data, codes_mapping)

    load = Load("Cancun", "cancun")
    # Adding partial state root
    pre_state_root = state_root(load.json_to_state(pre_state))

    # Generate genesis block header
    parent_block = zkpi_data["ancestors"][0]
    # Modify parent state root to be the state root of the pre-state (partial)
    parent_block["stateRoot"] = "0x" + pre_state_root.hex()

    # Convert block parameters
    block_parameters = create_eels_block_parameters(zkpi_data["block"])
    # We modify parent hash to be the hash of the modified parent block
    block_parameters["blockHeader"]["parentHash"] = (
        "0x" + keccak256(rlp.encode(load.json_to_header(parent_block))).hex()
    )

    # Create the final fixture format
    fixture = {
        "genesisBlockHeader": parent_block,
        "newBlockParameters": block_parameters,
        "pre": pre_state,
        "chainId": zkpi_data["chainConfig"].get("chainId", 1),
    }

    # Sanity checks
    block = Block(
        header=load.json_to_header(fixture["newBlockParameters"]["blockHeader"]),
        transactions=tuple(
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
            )  # Non-legacy txs are hex strings
            for tx in fixture["newBlockParameters"]["transactions"]
        ),
        ommers=(),
        withdrawals=tuple(
            Withdrawal(
                index=U64(int(w["index"], 16)),
                validator_index=U64(int(w["validatorIndex"], 16)),
                address=Address(hex_to_bytes(w["address"])),
                amount=U256(int(w["amount"], 16)),
            )
            for w in fixture["newBlockParameters"]["withdrawals"]
        ),
    )

    genesis_block = Block(
        header=load.json_to_header(fixture["genesisBlockHeader"]),
        transactions=(),
        ommers=(),
        withdrawals=(),
    )

    blockchain = BlockChain(
        blocks=[genesis_block],
        state=load.json_to_state(fixture["pre"]),
        chain_id=U64(fixture["chainId"]),
    )

    # Apply state root to get partial MPT state root
    apply_body_output = _state_transition(blockchain, block)
    print(f"State root: 0x{apply_body_output.state_root.hex()}")
    print(f"Transactions root: 0x{apply_body_output.transactions_root.hex()}")
    print(f"Receipts root: 0x{apply_body_output.receipt_root.hex()}")

    post_state_root = state_root(blockchain.state)
    fixture["newBlockParameters"]["blockHeader"]["stateRoot"] = (
        "0x" + post_state_root.hex()
    )

    # Create output file path with same name in eels directory
    output_file = script_dir / "data" / "eels" / zkpi_file.name
    output_file.parent.mkdir(parents=True, exist_ok=True)

    with open(output_file, "w") as f:
        json.dump(fixture, f, indent=2)

    print(f"Created EELS fixture at {output_file}")


def main():
    # Get the directory containing this script
    script_dir = Path(__file__).parent
    zkpi_dir = script_dir / "data" / "zkpi"

    # Check if a specific file was provided as argument
    if len(sys.argv) > 1:
        filename = sys.argv[1]
        zkpi_file = zkpi_dir / filename
        if not zkpi_file.exists():
            print(f"Error: File {filename} not found in {zkpi_dir}")
            sys.exit(1)
        process_zkpi_file(zkpi_file, script_dir)
    else:
        # Process all JSON files in the zkpi directory
        json_files = list(zkpi_dir.glob("*.json"))
        if not json_files:
            print(f"No JSON files found in {zkpi_dir}")
            sys.exit(1)

        print(f"Found {len(json_files)} JSON files to process")
        for zkpi_file in json_files:
            process_zkpi_file(zkpi_file, script_dir)

        print("Finished processing all files")


if __name__ == "__main__":
    main()

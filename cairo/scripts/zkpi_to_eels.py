"""
This script converts zkpi preflight JSON files to JSON that can be loaded
to test state transition with real L1 data. It can process a single file
or all JSON files in the zkpi directory.
"""

import argparse
import json
import logging
from pathlib import Path
from typing import Any, Dict

from ethereum.cancun.blocks import Block, Withdrawal
from ethereum.cancun.fork import (
    BlockChain,
    apply_body,
    get_last_256_block_hashes,
    state_transition,
)
from ethereum.cancun.fork_types import Address
from ethereum.cancun.transactions import LegacyTransaction, encode_transaction
from ethereum.cancun.vm.gas import calculate_excess_blob_gas
from ethereum.crypto.hash import keccak256
from ethereum.utils.hexadecimal import hex_to_bytes, hex_to_u256, hex_to_uint
from ethereum_spec_tools.evm_tools.loaders.fixture_loader import Load
from ethereum_spec_tools.evm_tools.loaders.fork_loader import ForkLoad
from ethereum_spec_tools.evm_tools.loaders.transaction_loader import TransactionLoad
from ethereum_types.bytes import Bytes, Bytes0
from ethereum_types.numeric import U64, U256

from eth_rpc import EthereumRPC

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
    """
    EMPTY_STORAGE_ROOT = (
        "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
    )
    EMPTY_CODE_HASH = "0x" + keccak256(b"").hex()
    EMPTY_ACCOUNT = {
        "balance": "0x0",
        "nonce": "0x0",
        "code": "0x",
        "storage": {},
    }

    state = {}
    eth = EthereumRPC.from_env()
    for account_proof in zkpi_data["preStateProofs"]:
        code = code_hashes.get(account_proof["codeHash"], "0x")
        if code == "0x" and account_proof["codeHash"] not in (
            EMPTY_CODE_HASH,
            f"0x{0:064x}",
        ):
            logger.info(
                f"Code hash {account_proof['codeHash']} not found in zkpi data for address {account_proof['address']}, fetching from node"
            )
            code = (
                "0x" + eth.get_code(Address.fromhex(account_proof["address"][2:])).hex()
            )
            code_hashes[account_proof["codeHash"]] = code

        account_state = {
            "balance": account_proof["balance"],
            "nonce": hex(account_proof.get("nonce", 0)),
            "code": code,
            "storage": {},
        }

        if account_state == EMPTY_ACCOUNT:
            logger.debug(
                f"empty account for address {account_proof['address']}, skipping"
            )
            continue

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
    """
    tx = tx.copy()
    tx["gasLimit"] = tx.pop("gas")
    tx["data"] = tx.pop("input")
    tx["to"] = tx["to"] if tx["to"] is not None else ""
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


def process_zkpi_file(zkpi_file: Path, do_check: bool = False) -> None:
    """
    Process a single ZKPI file and convert it to EELS format.

    Args:
        zkpi_file: Path to the ZKPI file
        do_check: Whether to perform sanity check on the fixture
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
        "newBlockHash": zkpi_data["block"]["hash"],
        "ancestors": zkpi_data["ancestors"][::-1],
    }

    if do_check:
        logger.info("Performing sanity check on fixture...")
        sanity_check_fixture(fixture)
    else:
        logger.info("Skipping sanity check (use --check to enable)")

    output_file = zkpi_file.parents[1] / "eels" / zkpi_file.name
    output_file.parent.mkdir(parents=True, exist_ok=True)

    with open(output_file, "w") as f:
        json.dump(fixture, f, indent=2)

    logger.info(f"Created EELS fixture at {output_file}")


def sanity_check_fixture(fixture: Dict[str, Any]) -> None:
    load = Load("Cancun", "cancun")
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
    blocks = [
        Block(
            header=load.json_to_header(ancestor),
            transactions=(),
            ommers=(),
            withdrawals=(),
        )
        for ancestor in fixture["ancestors"]
    ]
    chain = BlockChain(
        blocks=blocks,
        state=load.json_to_state(fixture["pre"]),
        chain_id=U64(fixture["chainId"]),
    )

    # TODO: Need to patch state_root, remove when we have a working partial MPT
    output = apply_body(
        state=chain.state,
        block_hashes=get_last_256_block_hashes(chain),
        coinbase=block.header.coinbase,
        block_number=block.header.number,
        base_fee_per_gas=block.header.base_fee_per_gas,
        block_gas_limit=block.header.gas_limit,
        block_time=block.header.timestamp,
        prev_randao=block.header.prev_randao,
        transactions=block.transactions,
        chain_id=chain.chain_id,
        withdrawals=block.withdrawals,
        parent_beacon_block_root=block.header.parent_beacon_block_root,
        excess_blob_gas=calculate_excess_blob_gas(chain.blocks[-1].header),
    )
    block = Block(
        header=load.json_to_header(
            {
                **fixture["newBlockParameters"]["blockHeader"],
                "stateRoot": "0x" + output.state_root.hex(),
            }
        ),
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
    chain = BlockChain(
        blocks=blocks,
        state=load.json_to_state(fixture["pre"]),
        chain_id=U64(fixture["chainId"]),
    )
    # TODO: end of tmp section
    state_transition(chain, block)


def main():
    parser = argparse.ArgumentParser(description="Convert ZKPI files to EELS format")
    parser.add_argument("path", help="Path to ZKPI file or directory")
    parser.add_argument(
        "--check",
        action="store_true",
        default=False,
        help="Perform sanity check on generated fixtures",
    )
    args = parser.parse_args()

    path = Path(args.path)

    if path.is_file():
        process_zkpi_file(path, args.check)
    elif path.is_dir():
        zkpi_files = list(path.glob("**/*.json"))
        if not zkpi_files:
            logger.error(f"No zkpi files found in {path}")
        else:
            logger.info(f"Processing {len(zkpi_files)} zkpi files in {path}...")
            for zkpi_file in zkpi_files:
                process_zkpi_file(zkpi_file, args.check)
    else:
        raise ValueError(f"Path {path} does not exist")


if __name__ == "__main__":
    main()

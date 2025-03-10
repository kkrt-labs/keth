"""
Prove an Ethereum block using Keth given a block number.
Fetches zkpi data, converts it to EELS/Keth format, and runs it through the Keth.
"""

import argparse
from dataclasses import dataclass
import json
import logging
from pathlib import Path
from typing import Any, Dict, Tuple

from ethereum.cancun.blocks import Block, Withdrawal
from ethereum.cancun.fork import (
    BlockChain,
    apply_body,
    get_last_256_block_hashes,
)
from ethereum.cancun.fork_types import Address
from ethereum.cancun.transactions import (
    LegacyTransaction,
)
from ethereum.cancun.vm.gas import calculate_excess_blob_gas
from ethereum.utils.hexadecimal import hex_to_bytes, hex_to_u256, hex_to_uint
from ethereum_spec_tools.evm_tools.loaders.fixture_loader import Load
from ethereum_types.bytes import Bytes, Bytes0
from ethereum_types.numeric import U64, U256
from scripts.zkpi_to_eels import process_zkpi_file

from ethereum_types.bytes import Bytes32

from cairo_addons.vm import run_proof_mode
from tests.ef_tests.helpers.load_state_tests import convert_defaultdict

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


@dataclass
class PublicInputs:
    prestate_root: Bytes32
    poststate_root: Bytes32
    block_hash: Bytes32


@dataclass
class PrivateInputs:
    block: Block
    blockchain: BlockChain

def zkpi_fixture(zkpi_path) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    with open(zkpi_path, "r") as f:
        fixture = json.load(f)

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
        state=convert_defaultdict(load.json_to_state(fixture["pre"])),
        chain_id=U64(fixture["chainId"]),
    )

    # TODO: Remove when we have a working partial MPT
    state_root = apply_body(
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
        calculate_excess_blob_gas(chain.blocks[-1].header),
    ).state_root
    block = Block(
        header=load.json_to_header(
            {
                **fixture["newBlockParameters"]["blockHeader"],
                "stateRoot": "0x" + state_root.hex(),
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
        state=convert_defaultdict(load.json_to_state(fixture["pre"])),
        chain_id=U64(fixture["chainId"]),
    )

    public_inputs = {
        "prestate_root": Bytes32(bytes.fromhex(fixture["newBlockParameters"]["blockHeader"]["stateRoot"].removeprefix("0x"))),
        "poststate_root": Bytes32(bytes.fromhex(fixture["ancestors"][-1]["stateRoot"].removeprefix("0x"))),
        "block_hash": Bytes32(bytes.fromhex(fixture["newBlockHash"].removeprefix("0x"))),
    }
    private_inputs = {
        "block": block,
        "blockchain": chain,
    }
    return public_inputs, private_inputs

def main():
    parser = argparse.ArgumentParser(description="Prove an Ethereum block using Keth")
    parser.add_argument("block_number", type=int, help="Block number to prove")
    parser.add_argument(
        "--output-dir", type=Path, default=Path("output"), help="Output directory"
    )
    args = parser.parse_args()

    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    # Fetch zkpi data
    logger.info(f"Fetching zkpi data for block {args.block_number}")
    path = Path(f"data/1/eels/{args.block_number}.json")
    public_inputs, private_inputs = zkpi_fixture(path)

    # Run Keth
    logger.info(f"Running Keth for block {args.block_number}")
    run_proof_mode(
        entrypoint="main",
        public_inputs=public_inputs,
        private_inputs=private_inputs,
        compiled_program_path="./main_compiled.json",
        output_dir=output_dir,
    )

    logger.info(f"Proof artifacts saved to {output_dir}")


if __name__ == "__main__":
    main()

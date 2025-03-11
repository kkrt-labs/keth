"""
Prove an Ethereum block using Keth given a block number.
Fetches zkpi data, converts it to EELS/Keth format, and runs it through the Keth.
"""

import argparse
import json
import logging
from dataclasses import dataclass
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
from ethereum_types.bytes import Bytes, Bytes0, Bytes32
from ethereum_types.numeric import U64, U256

from cairo_addons.vm import run_proof_mode
from tests.ef_tests.helpers.load_state_tests import convert_defaultdict

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


def init_tracer():
    """Initialize the logger "trace" mode."""
    import logging

    from colorama import Fore, Style, init

    init()

    # Define TRACE level
    TRACE_LEVEL = logging.DEBUG - 5
    logging.addLevelName(TRACE_LEVEL, "TRACE")

    # Custom trace methods for Logger instances
    def trace(self, message, *args, **kwargs):
        if self.isEnabledFor(TRACE_LEVEL):
            colored_msg = f"{Fore.YELLOW}TRACE{Style.RESET_ALL} {message}"
            print(colored_msg)

    def trace_cairo(self, message, *args, **kwargs):
        if self.isEnabledFor(TRACE_LEVEL):
            colored_msg = f"{Fore.YELLOW}TRACE{Style.RESET_ALL} [CAIRO] {message}"
            print(colored_msg)

    def trace_eels(self, message, *args, **kwargs):
        if self.isEnabledFor(TRACE_LEVEL):
            colored_msg = f"{Fore.YELLOW}TRACE{Style.RESET_ALL} [EELS] {message}"
            print(colored_msg)

    def debug_cairo(self, message, *args, **kwargs):
        if self.isEnabledFor(logging.DEBUG):
            colored_msg = f"{Fore.BLUE}DEBUG{Style.RESET_ALL} [DEBUG-CAIRO] {message}"
            print(colored_msg)

    # Patch the logging module with our new trace methods
    setattr(logging, "TRACE", TRACE_LEVEL)
    setattr(logging.getLoggerClass(), "trace", trace)
    setattr(logging.getLoggerClass(), "trace_cairo", trace_cairo)
    setattr(logging.getLoggerClass(), "trace_eels", trace_eels)
    setattr(logging.getLoggerClass(), "debug_cairo", debug_cairo)


@dataclass
class PublicInputs:
    pre_state_root: Bytes32
    post_state_root: Bytes32
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
        "pre_state_root": Bytes32(
            bytes.fromhex(
                fixture["newBlockParameters"]["blockHeader"]["stateRoot"].removeprefix(
                    "0x"
                )
            )
        ),
        "post_state_root": Bytes32(
            bytes.fromhex(fixture["ancestors"][-1]["stateRoot"].removeprefix("0x"))
        ),
        "block_hash": Bytes32(
            bytes.fromhex(fixture["newBlockHash"].removeprefix("0x"))
        ),
    }
    private_inputs = {
        "block": block,
        "blockchain": chain,
    }
    return public_inputs, private_inputs


def main():
    init_tracer()
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

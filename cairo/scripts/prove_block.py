"""
Prove an Ethereum block using Keth given a block number.
Fetches zkpi data, converts it to EELS/Keth format, and generates a proof.
"""

import argparse
import json
import logging
from pathlib import Path
from typing import Any, Dict, Optional

from ethereum.cancun.blocks import Block, Withdrawal
from ethereum.cancun.fork import BlockChain, apply_body, get_last_256_block_hashes
from ethereum.cancun.fork_types import Address
from ethereum.cancun.transactions import LegacyTransaction
from ethereum.cancun.vm.gas import calculate_excess_blob_gas
from ethereum.utils.hexadecimal import hex_to_bytes, hex_to_u256, hex_to_uint
from ethereum_spec_tools.evm_tools.loaders.fixture_loader import Load
from ethereum_types.bytes import Bytes, Bytes0, Bytes32
from ethereum_types.numeric import U64, U256

from cairo_addons.vm import run_proof_mode
from tests.ef_tests.helpers.load_state_tests import prepare_state

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

CANCUN_FORK_BLOCK = 19426587  # First Cancun block


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description="Prove an Ethereum block using Keth")
    parser.add_argument(
        "block_number",
        type=int,
        help="Ethereum block number to prove (Cancun fork or later)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("output"),
        help="Directory to save proof artifacts (default: ./output)",
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=Path("data/1/eels"),
        help="Directory containing ZKPI JSON files (default: ./data/1/eels)",
    )
    parser.add_argument(
        "--compiled-program",
        type=Path,
        default=Path("build/main_compiled.json"),
        help="Path to compiled Cairo program (default: ./build/main_compiled.json)",
    )
    parser.add_argument(
        "--stwo-proof",
        action="store_true",
        help="Generate Stwo proof instead of prover inputs",
    )
    parser.add_argument(
        "--proof-path",
        type=Path,
        default=Path("output/proof.json"),
        help="Path to save the Stwo proof (required when --stwo-proof is used). Default: ./output/proof.json",
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="Verify the Stwo proof after generation (only used with --stwo-proof)",
    )
    return parser.parse_args()


def load_zkpi_fixture(zkpi_path: Path) -> Dict[str, Any]:
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
    logger.debug(f"Loading ZKPI file: {zkpi_path}")
    with open(zkpi_path, "r") as f:
        fixture = json.load(f)

    load = Load("Cancun", "cancun")

    # Convert block
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
            )
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

    # Convert ancestors
    blocks = [
        Block(
            header=load.json_to_header(ancestor),
            transactions=(),
            ommers=(),
            withdrawals=(),
        )
        for ancestor in fixture["ancestors"]
    ]

    # Create blockchain
    chain = BlockChain(
        blocks=blocks,
        state=prepare_state(load.json_to_state(fixture["pre"])),
        chain_id=U64(fixture["chainId"]),
    )

    # TODO: Remove when partial MPT is implemented
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

    # Recreate block with computed state root
    block = Block(
        header=load.json_to_header(
            {
                **fixture["newBlockParameters"]["blockHeader"],
                "stateRoot": "0x" + state_root.hex(),
            }
        ),
        transactions=block.transactions,
        ommers=(),
        withdrawals=block.withdrawals,
    )
    chain = BlockChain(
        blocks=blocks,
        state=prepare_state(load.json_to_state(fixture["pre"])),
        chain_id=U64(fixture["chainId"]),
    )

    # Prepare inputs
    program_inputs = {
        "block": block,
        "blockchain": chain,
        "block_hash": Bytes32(
            bytes.fromhex(fixture["newBlockHash"].removeprefix("0x"))
        ),
    }

    return program_inputs


def prove_block(
    block_number: int,
    output_dir: Path,
    zkpi_path: Path,
    compiled_program: Path,
    stwo_proof: bool = False,
    proof_path: Optional[Path] = None,
    verify: bool = False,
) -> None:
    """Run the proof generation process for the given block."""
    # Ensure output directory exists
    output_dir.mkdir(parents=True, exist_ok=True)

    # Validate compiled program
    if not compiled_program.is_file():
        raise FileNotFoundError(f"Compiled program not found: {compiled_program}")

    # Load ZKPI data
    logger.info(f"Fetching ZKPI data for block {block_number}")
    program_inputs = load_zkpi_fixture(zkpi_path)

    # Generate proof
    logger.info(f"Running Keth for block {block_number}")
    run_proof_mode(
        entrypoint="main",
        program_inputs=program_inputs,
        compiled_program_path=str(compiled_program.absolute()),
        output_dir=str(output_dir.absolute()),
        stwo_proof=stwo_proof,
        proof_path=str(proof_path.absolute()) if proof_path else None,
        verify=verify,
    )

    if stwo_proof:
        logger.info(f"Stwo proof saved to {proof_path}")
        if verify:
            logger.info("Proof verified successfully")
    else:
        logger.info(f"Proof artifacts saved to {output_dir}")


def main() -> int:
    """Main entry point for proving an Ethereum block."""
    args = parse_args()

    if args.block_number < CANCUN_FORK_BLOCK:
        logger.error(
            f"Block {args.block_number} is before Cancun fork ({CANCUN_FORK_BLOCK})"
        )
        return 1

    zkpi_path = args.data_dir / f"{args.block_number}.json"

    try:
        prove_block(
            args.block_number,
            args.output_dir,
            zkpi_path,
            args.compiled_program,
            args.stwo_proof,
            args.proof_path,
            args.verify,
        )
        return 0
    except FileNotFoundError as e:
        logger.error(f"File error: {e}")
        return 1
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in ZKPI file {zkpi_path}: {e}")
        return 1
    except (KeyError, ValueError) as e:
        logger.error(f"Data error: {e}")
        return 1
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return 1
    except KeyboardInterrupt:
        logger.info("Operation cancelled by user")
        return 130


if __name__ == "__main__":
    main()

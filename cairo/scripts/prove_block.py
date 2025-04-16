"""
Prove an Ethereum block using Keth given a block number.
Fetches zkpi data, converts it to EELS/Keth format, and generates a proof.
"""

import argparse
import json
import logging
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, Union

from ethereum.cancun.blocks import Block, Withdrawal
from ethereum.cancun.fork import (
    BlockChain,
)
from ethereum.cancun.fork_types import Address
from ethereum.cancun.state import State
from ethereum.cancun.transactions import (
    LegacyTransaction,
    encode_transaction,
)
from ethereum.utils.hexadecimal import hex_to_bytes, hex_to_u256, hex_to_uint
from ethereum_spec_tools.evm_tools.loaders.fork_loader import ForkLoad
from ethereum_spec_tools.evm_tools.loaders.transaction_loader import TransactionLoad
from ethereum_types.bytes import Bytes, Bytes0
from ethereum_types.numeric import U64, U256

from cairo_addons.vm import run_proof_mode
from mpt.ethereum_tries import ZkPi
from utils.fixture_loader import LoadKethFixture, map_code_hashes_to_code

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
        default=Path("data/inputs/1"),
        help="Directory containing prover inputs (ZK-PI) (default: ./data/inputs/1)",
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


def load_pre_state(data: Dict[str, Any]) -> State:
    """Load the pre-state from the fixture."""
    zkpi = ZkPi.from_data(data)
    pre_state = zkpi.pre_state
    return pre_state


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


def prove_block(
    block_number: int,
    output_dir: Union[Path, str],
    zkpi_path: Union[Path, str],
    compiled_program: Union[Path, str],
    stwo_proof: bool = False,
    proof_path: Optional[Union[Path, str]] = None,
    verify: bool = False,
) -> None:
    """Run the proof generation process for the given block."""
    output_dir = Path(output_dir)
    # Ensure output directory exists
    output_dir.mkdir(parents=True, exist_ok=True)

    # Validate compiled program
    compiled_program = Path(compiled_program)
    if not compiled_program.is_file():
        raise FileNotFoundError(
            f"Compiled program not found: {compiled_program} - Consider running `uv run compile_keth`"
        )

    # Load ZKPI data
    logger.info(f"Fetching prover inputs for block {block_number}")
    program_input = load_zkpi_fixture(zkpi_path)

    # Generate proof
    if proof_path:
        proof_path = Path(proof_path)
    logger.info(f"Running Keth for block {block_number}")
    run_proof_mode(
        entrypoint="main",
        program_input=program_input,
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
    except KeyboardInterrupt:
        logger.info("Operation cancelled by user")
        return 130


if __name__ == "__main__":
    main()

"""
Prove an Ethereum block using Keth given a block number.
Fetches zkpi data, converts it to EELS/Keth format, and runs it through the Keth.
"""

import argparse
import json
import logging
from pathlib import Path
from typing import Any, Dict

from scripts.zkpi_to_eels import (  # Reuse existing conversion logic
    process_zkpi_file,
)

from cairo_addons.vm import CairoRunner  # PyO3 binding to Rust CairoRunner

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


def fetch_zkpi_data(block_number: int) -> Dict[str, Any]:
    """
    Fetch zkpi preflight JSON for a given block number.
    """
    # TODO: In production, fetch from an API
    zkpi_file = Path(f"cairo/zkpi/block_{block_number}.json")
    if not zkpi_file.exists():
        raise FileNotFoundError(f"ZKPI data for block {block_number} not found")
    with open(zkpi_file, "r") as f:
        return json.load(f)


def convert_to_keth_inputs(eels_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Convert EELS data to Keth-compatible inputs.
    - Public inputs: pre-state root, post-state root, block hash
    - Private inputs: state object
    """
    block_header = eels_data["newBlockParameters"]["blockHeader"]
    public_inputs = {
        "pre_state_root": eels_data["pre"]["stateRoot"],
        "post_state_root": block_header["stateRoot"],
        "block_hash": block_header["hash"],  # Assuming hash is available or computed
    }
    private_inputs = {
        "block": json.dumps(eels_data["newBlockParameters"]),
        "pre_state": json.dumps(eels_data["pre"]),
    }
    return {"public": public_inputs, "private": private_inputs}


def main():
    parser = argparse.ArgumentParser(description="Prove an Ethereum block using Keth")
    parser.add_argument("block_number", type=int, help="Block number to prove")
    parser.add_argument(
        "--output-dir", type=Path, default=Path("output"), help="Output directory"
    )
    args = parser.parse_args()

    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    # Step 1: Fetch zkpi data
    logger.info(f"Fetching zkpi data for block {args.block_number}")
    zkpi_data = fetch_zkpi_data(args.block_number)

    # Step 2: Convert to EELS format
    zkpi_file = output_dir / f"block_{args.block_number}_zkpi.json"
    with open(zkpi_file, "w") as f:
        json.dump(zkpi_data, f)
    process_zkpi_file(zkpi_file)  # Outputs to eels/block_<number>.json
    eels_file = output_dir / "eels" / f"block_{args.block_number}_zkpi.json"
    with open(eels_file, "r") as f:
        eels_data = json.load(f)

    # Step 3: Convert to Keth inputs
    keth_inputs = convert_to_keth_inputs(eels_data)

    # Step 4: Run Keth
    logger.info(f"Running Keth for block {args.block_number}")
    runner = CairoRunner(
        program=Path("cairo/programs/prove_block.cairo"),  # Compiled Cairo program
        layout="all_cairo",
        proof_mode=True,
    )
    runner.initialize_segments()
    runner.load_data(
        runner.program_base, [keth_inputs["public"]["pre_state_root"]]
    )  # Example
    runner.run_proof_mode(
        entrypoint="main",
        public_inputs=keth_inputs["public"],
        private_inputs=keth_inputs["private"],
        output_dir=output_dir,
    )

    logger.info(f"Proof artifacts saved to {output_dir}")


if __name__ == "__main__":
    main()

"""Step management and handling for Keth CLI."""

import json
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional

from rich.console import Console

from mpt.ethereum_tries import EthereumTrieTransitionDB
from utils.fixture_loader import (
    load_body_input,
    load_mpt_diff_input,
    load_teardown_input,
    load_zkpi_fixture,
)

from .config import KethConfig
from .exceptions import (
    InvalidBranchIndexError,
    InvalidStepParametersError,
    MissingSegmentOutputError,
)

console = Console()


class Step(str, Enum):
    """Execution steps for Keth processing."""

    MAIN = "main"
    INIT = "init"
    BODY = "body"
    TEARDOWN = "teardown"
    AGGREGATOR = "aggregator"
    MPT_DIFF = "mpt_diff"


class StepHandler:
    """Handles step-specific logic for different execution steps."""

    @staticmethod
    def validate_step_params(
        step: Step,
        start_index: Optional[int],
        chunk_size: Optional[int],
        branch_index: Optional[int] = None,
    ) -> None:
        """Validate step-specific parameters."""
        if step == Step.BODY:
            _validate_body_params(start_index, chunk_size)
        elif step == Step.MPT_DIFF:
            _validate_mpt_diff_params(branch_index)

    @staticmethod
    def load_program_input(
        step: Step,
        zkpi_path: Path,
        config: KethConfig,
        start_index: Optional[int] = None,
        chunk_size: Optional[int] = None,
        branch_index: Optional[int] = None,
    ) -> Dict[str, Any]:
        """Load program input based on step type."""
        match step:
            case Step.BODY:
                return load_body_input(
                    zkpi_path=zkpi_path,
                    start_index=start_index,
                    chunk_size=chunk_size,
                )
            case Step.TEARDOWN:
                return load_teardown_input(zkpi_path)
            case Step.MPT_DIFF:
                if branch_index is None:
                    raise InvalidStepParametersError(
                        step.value, "branch_index is required for mpt_diff step"
                    )
                return load_mpt_diff_input(
                    zkpi_path=zkpi_path,
                    branch_index=branch_index,
                )
            case Step.AGGREGATOR:
                return _load_aggregator_input(zkpi_path, config)
            case _:
                return load_zkpi_fixture(zkpi_path)

    @staticmethod
    def get_output_filename(
        step: Step,
        block_number: int,
        config: KethConfig,
        start_index: Optional[int] = None,
        chunk_size: Optional[int] = None,
        branch_index: Optional[int] = None,
        file_type: str = None,
        cairo_pie: bool = False,
    ) -> str:
        """Generate output filename based on step and parameters."""
        if file_type is None:
            file_type = config.PROVER_INPUT_PREFIX

        # Determine base filename pattern
        if step == Step.BODY and start_index is not None and chunk_size is not None:
            base_name = f"{block_number}_body_{start_index}_{chunk_size}"
        elif step == Step.INIT:
            base_name = f"{block_number}_init"
        elif step == Step.TEARDOWN:
            base_name = f"{block_number}_teardown"
        elif step == Step.AGGREGATOR:
            base_name = f"{block_number}_aggregator"
        elif step == Step.MPT_DIFF and branch_index is not None:
            base_name = f"{block_number}_mpt_diff_{branch_index}"
        else:
            base_name = f"{block_number}"

        # Determine file extension based on output type
        if cairo_pie:
            return f"{config.CAIRO_PIE_PREFIX}_{base_name}{config.CAIRO_PIE_EXT}"
        else:
            return f"{file_type}_{base_name}"

    @staticmethod
    def get_proof_filename(
        step: Step,
        config: KethConfig,
        start_index: Optional[int] = None,
        chunk_size: Optional[int] = None,
        branch_index: Optional[int] = None,
    ) -> str:
        """Generate proof filename based on step."""
        match step:
            case Step.INIT:
                return f"{config.PROOF_PREFIX}_init{config.PROOF_EXT}"
            case Step.TEARDOWN:
                return f"{config.PROOF_PREFIX}_teardown{config.PROOF_EXT}"
            case Step.BODY:
                return f"{config.PROOF_PREFIX}_body_{start_index}_{chunk_size}{config.PROOF_EXT}"
            case Step.AGGREGATOR:
                return f"{config.PROOF_PREFIX}_aggregator{config.PROOF_EXT}"
            case Step.MPT_DIFF:
                return (
                    f"{config.PROOF_PREFIX}_mpt_diff_{branch_index}{config.PROOF_EXT}"
                )
            case _:
                return f"{config.PROOF_PREFIX}{config.PROOF_EXT}"

    @staticmethod
    def get_default_program(step: Step, config: KethConfig) -> Path:
        """Returns the default compiled program path based on step."""
        return config.COMPILED_PROGRAMS.get(
            step.value, config.COMPILED_PROGRAMS["main"]
        )


def _validate_body_params(
    start_index: Optional[int], chunk_size: Optional[int]
) -> None:
    """Validate that body step parameters are provided correctly."""
    if start_index is None or chunk_size is None:
        raise InvalidStepParametersError(
            Step.BODY.value,
            "--start-index and --len parameters are required for body step",
        )
    if start_index < 0:
        raise InvalidStepParametersError(
            Step.BODY.value, "start-index must be non-negative"
        )
    if chunk_size <= 0:
        raise InvalidStepParametersError(Step.BODY.value, "len must be positive")


def _validate_mpt_diff_params(branch_index: Optional[int]) -> None:
    """Validate that mpt_diff step parameters are provided correctly."""
    if branch_index is None:
        raise InvalidStepParametersError(
            Step.MPT_DIFF.value,
            "--branch-index parameter is required for mpt_diff step",
        )
    if branch_index < 0 or branch_index > 15:
        raise InvalidBranchIndexError(branch_index)


def _load_aggregator_input(zkpi_path: Path, config: KethConfig) -> Dict[str, Any]:
    """Load aggregator input by discovering and loading segment outputs."""
    # Determine the proving run directory from the zkpi_path
    block_dir = zkpi_path.parent
    block_number = int(block_dir.name)

    # Find the latest proving run directory
    proving_run_dirs = [
        d for d in block_dir.iterdir() if d.is_dir() and d.name.isdigit()
    ]
    if not proving_run_dirs:
        raise MissingSegmentOutputError("proving run", str(block_dir))

    latest_proving_run_dir = max(proving_run_dirs, key=lambda d: int(d.name))

    console.print(
        f"[blue]Loading segment outputs from proving run directory: {latest_proving_run_dir}[/]"
    )

    # Read init output
    init_outputs = _find_step_outputs(latest_proving_run_dir, Step.INIT, block_number)
    if not init_outputs:
        raise MissingSegmentOutputError(Step.INIT.value, str(latest_proving_run_dir))
    init_output = _read_program_output(init_outputs[0])
    console.print(f"[green]✓[/] Loaded init output: {len(init_output)} values")

    # Read body outputs
    body_outputs = _find_step_outputs(latest_proving_run_dir, Step.BODY, block_number)
    if not body_outputs:
        raise MissingSegmentOutputError(Step.BODY.value, str(latest_proving_run_dir))
    body_outputs.sort(key=_extract_body_start_index)
    body_output_data = [
        _read_program_output(output_file) for output_file in body_outputs
    ]
    console.print(f"[green]✓[/] Loaded {len(body_output_data)} body chunk outputs")

    # Read teardown output
    teardown_outputs = _find_step_outputs(
        latest_proving_run_dir, Step.TEARDOWN, block_number
    )
    if not teardown_outputs:
        raise MissingSegmentOutputError(
            Step.TEARDOWN.value, str(latest_proving_run_dir)
        )
    teardown_output = _read_program_output(teardown_outputs[0])
    console.print(f"[green]✓[/] Loaded teardown output: {len(teardown_output)} values")

    # Read MPT diff outputs (optional)
    mpt_diff_outputs = _find_step_outputs(
        latest_proving_run_dir, Step.MPT_DIFF, block_number
    )
    mpt_diff_output_data = []
    if mpt_diff_outputs:
        mpt_diff_outputs.sort(key=_extract_mpt_diff_branch_index)
        mpt_diff_output_data = [
            _read_program_output(output_file) for output_file in mpt_diff_outputs
        ]
        console.print(
            f"[green]✓[/] Loaded {len(mpt_diff_output_data)} MPT diff outputs"
        )

    # Load program hashes
    program_hashes = _load_program_hashes(config)

    # Get program hashes for each step
    keth_segment_program_hashes = {
        "init": _get_step_program_hash(Step.INIT, program_hashes, config),
        "body": _get_step_program_hash(Step.BODY, program_hashes, config),
        "teardown": _get_step_program_hash(Step.TEARDOWN, program_hashes, config),
    }

    # Add mpt_diff program hash if we have mpt_diff outputs
    if mpt_diff_output_data:
        keth_segment_program_hashes["mpt_diff"] = _get_step_program_hash(
            Step.MPT_DIFF, program_hashes, config
        )

    tries = EthereumTrieTransitionDB.from_json(zkpi_path)

    # Construct aggregator input
    return {
        "keth_segment_outputs": [init_output] + body_output_data + [teardown_output],
        "keth_segment_program_hashes": keth_segment_program_hashes,
        "n_body_chunks": len(body_output_data),
        "n_mpt_diff_chunks": len(mpt_diff_output_data),
        "mpt_diff_segment_outputs": mpt_diff_output_data,
        "left_mpt": tries.state_root,
        "right_mpt": tries.post_state_root,
        "node_store": tries.nodes,
    }


def _read_program_output(output_file_path: Path) -> List[int]:
    """Read program output from a .run_output.txt file."""
    try:
        with open(output_file_path, "r") as f:
            content = f.read().strip()
            if not content:
                return []
            return [int(x) for x in content.split()]
    except (FileNotFoundError, ValueError) as e:
        raise MissingSegmentOutputError("program output", str(output_file_path)) from e


def _find_step_outputs(
    proving_run_dir: Path, step: Step, block_number: int
) -> List[Path]:
    """Find all output files for a given step in the proving run directory."""
    if step == Step.INIT:
        pattern = f"*{block_number}_init*.run_output.txt"
    elif step == Step.TEARDOWN:
        pattern = f"*{block_number}_teardown*.run_output.txt"
    elif step == Step.BODY:
        pattern = f"*{block_number}_body_*.run_output.txt"
    elif step == Step.MPT_DIFF:
        pattern = f"*{block_number}_mpt_diff_*.run_output.txt"
    else:
        return []

    import glob

    return [Path(p) for p in glob.glob(str(proving_run_dir / pattern))]


def _extract_body_start_index(path: Path) -> int:
    """Extract start_index from body filename."""
    parts = path.stem.split("_")
    for i, part in enumerate(parts):
        if part == "body" and i + 1 < len(parts):
            return int(parts[i + 1])
    return 0


def _extract_mpt_diff_branch_index(path: Path) -> int:
    """Extract branch_index from mpt_diff filename."""
    base_name = path.stem.split(".run_output")[0]
    parts = base_name.split("_")
    for i, part in enumerate(parts):
        if part == "diff" and i + 1 < len(parts):
            try:
                return int(parts[i + 1])
            except ValueError:
                return 0
    return 0


def _load_program_hashes(config: KethConfig) -> Dict[str, int]:
    """Load program hashes from the program_hashes.json file."""
    try:
        if not config.PROGRAM_HASHES_FILE.exists():
            console.print(
                f"[yellow]Warning: Program hashes file not found at {config.PROGRAM_HASHES_FILE}[/]"
            )
            return {}

        with open(config.PROGRAM_HASHES_FILE, "r") as f:
            program_hashes = json.load(f)

        console.print(
            f"[blue]Loaded program hashes from {config.PROGRAM_HASHES_FILE}[/]"
        )
        return program_hashes
    except Exception as e:
        console.print(f"[yellow]Warning: Failed to load program hashes: {e}[/]")
        return {}


def _get_step_program_hash(
    step: Step, program_hashes: Dict[str, int], config: KethConfig
) -> int:
    """Get the program hash for a given step from the loaded program hashes."""
    compiled_program_path = StepHandler.get_default_program(step, config)
    program_name = compiled_program_path.name

    if program_name in program_hashes:
        program_hash = program_hashes[program_name]
        console.print(
            f"[green]✓[/] Found {step.value} program hash: 0x{program_hash:x}"
        )
        return program_hash
    else:
        console.print(f"[yellow]Warning: Program hash not found for {program_name}[/]")
        return 0x0

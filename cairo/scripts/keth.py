"""
Keth CLI - A tool for generating execution traces and proofs for Ethereum blocks using STWO.

This CLI provides four main commands:
- trace: Generates the execution trace and serializes it as prover inputs from a block's ZK-PI
- prove: Generates a proof from the prover inputs
- verify: Verifies a proof
- e2e: Runs the full trace-generation, proving and verification pipeline
"""

import json
import logging
import traceback
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

import typer
from rich.console import Console
from rich.logging import RichHandler

from cairo_addons.rust_bindings.stwo_bindings import prove as run_prove
from cairo_addons.rust_bindings.stwo_bindings import verify as run_verify
from cairo_addons.rust_bindings.vm import generate_trace as run_generate_trace
from cairo_addons.rust_bindings.vm import run_end_to_end
from utils.fixture_loader import (
    PRAGUE_FORK_BLOCK,
    load_body_input,
    load_mpt_diff_input,
    load_teardown_input,
    load_zkpi_fixture,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(message)s",
    datefmt="[%X]",
    handlers=[RichHandler(rich_tracebacks=True)],
)
logger = logging.getLogger("keth")
console = Console()

app = typer.Typer(
    help="Keth - Generate execution traces and proofs for Ethereum blocks. Set LOG_FORMAT=[plain|json] to control Rust log output.",
    no_args_is_help=True,
)

DEFAULT_CHAIN_ID = 1


# Typer does not support Literal["main", "init"] in its type enforcement, so we use an Enum instead.
# See <https://typer.tiangolo.com/tutorial/parameter-types/enum/?h=enum>
class Step(str, Enum):
    MAIN = "main"
    INIT = "init"
    BODY = "body"
    TEARDOWN = "teardown"
    AGGREGATOR = "aggregator"
    MPT_DIFF = "mpt_diff"


@dataclass
class KethContext:
    """Shared context for Keth operations."""

    data_dir: Path
    chain_id: int
    block_number: int
    zkpi_version: str
    proving_run_id: str
    zkpi_path: Path
    proving_run_dir: Path

    @classmethod
    def create(
        cls,
        data_dir: Path,
        block_number: int,
        chain_id: Optional[int] = None,
        zkpi_version: str = "1",
        proving_run_id: Optional[str] = None,
    ) -> "KethContext":
        """Create a KethContext with automatic resolution of missing values."""
        # Resolve chain ID if not provided
        if chain_id is None:
            chain_id = cls._resolve_chain_id(data_dir, block_number, zkpi_version)

        # Validate ZKPI file exists
        zkpi_path = get_zkpi_path(data_dir, chain_id, block_number, zkpi_version)
        if not zkpi_path.exists():
            console.print(f"[red]Error: ZKPI file not found at {zkpi_path}[/]")
            raise typer.Exit(1)

        # Resolve proving run ID if not provided
        if proving_run_id is None:
            proving_run_id = get_next_proving_run_id(data_dir, chain_id, block_number)

        # Create proving run directory
        proving_run_dir = get_proving_run_dir(
            data_dir, chain_id, block_number, proving_run_id
        )
        proving_run_dir.mkdir(parents=True, exist_ok=True)

        return cls(
            data_dir=data_dir,
            chain_id=chain_id,
            block_number=block_number,
            zkpi_version=zkpi_version,
            proving_run_id=proving_run_id,
            zkpi_path=zkpi_path,
            proving_run_dir=proving_run_dir,
        )

    @staticmethod
    def _resolve_chain_id(data_dir: Path, block_number: int, zkpi_version: str) -> int:
        """Resolve chain ID from ZKPI file."""
        zkpi_path = get_zkpi_path(
            data_dir, DEFAULT_CHAIN_ID, block_number, zkpi_version
        )
        if not zkpi_path.exists():
            console.print(
                f"[red]Error: ZKPI file not found at {zkpi_path} and no chain ID provided[/]"
            )
            raise typer.Exit(1)
        return get_chain_id_from_zkpi(zkpi_path)


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
            validate_body_params(step, start_index, chunk_size)
        elif step == Step.MPT_DIFF:
            validate_mpt_diff_params(branch_index)

    @staticmethod
    def load_program_input(
        step: Step,
        zkpi_path: Path,
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
                    raise ValueError("branch_index is required for mpt_diff step")
                return load_mpt_diff_input(
                    zkpi_path=zkpi_path,
                    branch_index=branch_index,
                )
            case Step.AGGREGATOR:
                # The input of the aggregator must contain:
                # - output of the init step
                # - output of the body step(s)
                # - output of the teardown step
                # - program hashes of the init, body, and teardown steps
                # - number of body chunks ran
                # These values can only be obtained after running the init, body, and teardown steps
                # and getting the values back from the output files.

                # Determine the proving run directory from the zkpi_path
                # zkpi_path structure: data_dir/chain_id/block_number/zkpi.json
                # We need to find the latest proving run directory
                block_dir = zkpi_path.parent
                block_number = int(block_dir.name)

                # Find the latest proving run directory (highest numbered directory)
                proving_run_dirs = [
                    d for d in block_dir.iterdir() if d.is_dir() and d.name.isdigit()
                ]
                if not proving_run_dirs:
                    console.print(
                        f"[red]No proving run directories found in {block_dir}[/]"
                    )
                    raise typer.Exit(1)

                latest_proving_run_dir = max(
                    proving_run_dirs, key=lambda d: int(d.name)
                )

                console.print(
                    f"[blue]Loading segment outputs from proving run directory: {latest_proving_run_dir}[/]"
                )

                # Read init output
                init_outputs = find_step_outputs(
                    latest_proving_run_dir, Step.INIT, block_number
                )
                if not init_outputs:
                    console.print(
                        f"[red]No init output files found in {latest_proving_run_dir}[/]"
                    )
                    raise typer.Exit(1)
                init_output = read_program_output(init_outputs[0])
                console.print(
                    f"[green]✓[/] Loaded init output: {len(init_output)} values"
                )

                # Read body outputs (sorted by start_index)
                body_outputs = find_step_outputs(
                    latest_proving_run_dir, Step.BODY, block_number
                )
                if not body_outputs:
                    console.print(
                        f"[red]No body output files found in {latest_proving_run_dir}[/]"
                    )
                    raise typer.Exit(1)

                # Sort body outputs by start_index (extract from filename)
                def extract_body_start_index(path: Path) -> int:
                    # Extract start_index from filename like "prover_input_info_22615247_body_0_5.run_output.txt"
                    parts = path.stem.split("_")
                    for i, part in enumerate(parts):
                        if part == "body" and i + 1 < len(parts):
                            return int(parts[i + 1])
                    return 0

                body_outputs.sort(key=extract_body_start_index)
                body_output_data = [
                    read_program_output(output_file) for output_file in body_outputs
                ]
                console.print(
                    f"[green]✓[/] Loaded {len(body_output_data)} body chunk outputs"
                )

                # Read teardown output
                teardown_outputs = find_step_outputs(
                    latest_proving_run_dir, Step.TEARDOWN, block_number
                )
                if not teardown_outputs:
                    console.print(
                        f"[red]No teardown output files found in {latest_proving_run_dir}[/]"
                    )
                    raise typer.Exit(1)
                teardown_output = read_program_output(teardown_outputs[0])
                console.print(
                    f"[green]✓[/] Loaded teardown output: {len(teardown_output)} values"
                )

                # Read MPT diff outputs (optional - may not exist for older runs)
                mpt_diff_outputs = find_step_outputs(
                    latest_proving_run_dir, Step.MPT_DIFF, block_number
                )
                mpt_diff_output_data = []
                if mpt_diff_outputs:
                    # Sort MPT diff outputs by branch index
                    def extract_mpt_diff_branch_index(path: Path) -> int:
                        # Extract branch_index from filename like "prover_input_info_22615247_mpt_diff_0.run_output.txt"
                        # First split by .run_output to get the base name
                        base_name = path.stem.split(".run_output")[0]
                        parts = base_name.split("_")
                        for i, part in enumerate(parts):
                            if part == "diff" and i + 1 < len(parts):
                                try:
                                    return int(parts[i + 1])
                                except ValueError:
                                    return 0
                        return 0

                    mpt_diff_outputs.sort(key=extract_mpt_diff_branch_index)
                    mpt_diff_output_data = [
                        read_program_output(output_file)
                        for output_file in mpt_diff_outputs
                    ]
                    console.print(
                        f"[green]✓[/] Loaded {len(mpt_diff_output_data)} MPT diff outputs"
                    )

                # Load program hashes once
                program_hashes = load_program_hashes()

                # Get program hashes for each step
                init_program_hash = get_step_program_hash(Step.INIT, program_hashes)
                body_program_hash = get_step_program_hash(Step.BODY, program_hashes)
                teardown_program_hash = get_step_program_hash(
                    Step.TEARDOWN, program_hashes
                )
                mpt_diff_program_hash = get_step_program_hash(
                    Step.MPT_DIFF, program_hashes
                )

                # Build keth_segment_program_hashes dict
                keth_segment_program_hashes = {
                    "init": init_program_hash,
                    "body": body_program_hash,
                    "teardown": teardown_program_hash,
                    "mpt_diff": mpt_diff_program_hash,
                }

                # Add mpt_diff program hash if we have mpt_diff outputs
                if mpt_diff_output_data:
                    mpt_diff_program_hash = get_step_program_hash(
                        Step.MPT_DIFF, program_hashes
                    )
                    keth_segment_program_hashes["mpt_diff"] = mpt_diff_program_hash

                # Construct aggregator input
                aggregator_input = {
                    "keth_segment_outputs": [init_output]
                    + body_output_data
                    + [teardown_output],
                    "keth_segment_program_hashes": keth_segment_program_hashes,
                    "n_body_chunks": len(body_output_data),
                    "n_mpt_diff_chunks": len(mpt_diff_output_data),
                    "mpt_diff_segment_outputs": mpt_diff_output_data,
                }

                return aggregator_input
            case _:
                return load_zkpi_fixture(zkpi_path)

    @staticmethod
    def get_output_filename(
        step: Step,
        block_number: int,
        start_index: Optional[int] = None,
        chunk_size: Optional[int] = None,
        branch_index: Optional[int] = None,
        file_type: str = "prover_input_info",
        cairo_pie: bool = False,
    ) -> str:
        """Generate output filename based on step and parameters."""
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
            return f"cairo_pie_{base_name}.zip"
        else:
            return f"{file_type}_{base_name}"

    @staticmethod
    def get_proof_filename(
        step: Step,
        start_index: Optional[int] = None,
        chunk_size: Optional[int] = None,
        branch_index: Optional[int] = None,
    ) -> str:
        """Generate proof filename based on step."""
        match step:
            case Step.INIT:
                return "proof_init.json"
            case Step.TEARDOWN:
                return "proof_teardown.json"
            case Step.BODY:
                return f"proof_body_{start_index}_{chunk_size}.json"
            case Step.AGGREGATOR:
                return "proof_aggregator.json"
            case Step.MPT_DIFF:
                return f"proof_mpt_diff_{branch_index}.json"
            case _:
                return "proof.json"


def handle_command_error(operation: str) -> Callable:
    """Decorator to handle common command errors."""

    def decorator(func: Callable) -> Callable:
        def wrapper(*args, **kwargs):
            try:
                return func(*args, **kwargs)
            except Exception:
                console.print(
                    f"[red]Error {operation}:[/] {str(traceback.format_exc())}"
                )
                raise typer.Exit(1)

        return wrapper

    return decorator


# ============================================================================
# UTILITY FUNCTIONS (unchanged from original)
# ============================================================================


def read_program_output(output_file_path: Path) -> List[int]:
    """Read program output from a .run_output.txt file and parse it as a list of integers."""
    try:
        with open(output_file_path, "r") as f:
            content = f.read().strip()
            if not content:
                return []
            # Parse the output - assuming it's space or newline separated integers
            return [int(x) for x in content.split()]
    except (FileNotFoundError, ValueError) as e:
        console.print(
            f"[red]Error reading program output from {output_file_path}: {e}[/]"
        )
        raise typer.Exit(1)


def find_step_outputs(
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


def get_next_proving_run_id(data_dir: Path, chain_id: int, block_number: int) -> str:
    """Get the next sequential proving run ID for a given chain and block."""
    block_dir = data_dir / str(chain_id) / str(block_number)
    if not block_dir.exists():
        return "1"

    # Find existing proving run directories
    existing_runs = []
    for item in block_dir.iterdir():
        if item.is_dir() and item.name.isdigit():
            existing_runs.append(int(item.name))

    return str(max(existing_runs, default=0) + 1)


def get_zkpi_path(
    data_dir: Path, chain_id: int, block_number: int, version: str = "1"
) -> Path:
    """Get the path to the ZKPI file for a given chain, block, and version."""
    return data_dir / str(chain_id) / str(block_number) / "zkpi.json"


def get_proving_run_dir(
    data_dir: Path, chain_id: int, block_number: int, proving_run_id: str
) -> Path:
    """Get the proving run directory for a given chain, block, and proving run ID."""
    return data_dir / str(chain_id) / str(block_number) / proving_run_id


def get_chain_id_from_zkpi(zkpi_path: Path) -> int:
    """Extract chain ID from ZKPI file."""
    try:
        with open(zkpi_path, "r") as f:
            zkpi_data = json.load(f)
        return zkpi_data["chainConfig"]["chainId"]
    except (FileNotFoundError, KeyError, json.JSONDecodeError) as e:
        console.print(f"[red]Error reading chain ID from ZKPI file {zkpi_path}: {e}[/]")
        raise typer.Exit(1)


def validate_block_number(block_number: int) -> None:
    """Validate that the block number is after prague fork."""
    if block_number < PRAGUE_FORK_BLOCK:
        typer.echo(
            f"Error: Block {block_number} is before Prague fork ({PRAGUE_FORK_BLOCK})"
        )
        raise typer.Exit(1)


def get_default_program(step: Step) -> Path:
    """Returns the default compiled program path based on step"""
    step_to_program = {
        Step.MAIN: "build/main_compiled.json",
        Step.INIT: "build/init_compiled.json",
        Step.BODY: "build/body_compiled.json",
        Step.TEARDOWN: "build/teardown_compiled.json",
        Step.AGGREGATOR: "build/aggregator_compiled.json",
        Step.MPT_DIFF: "build/mpt_diff_compiled.json",
    }
    return Path(step_to_program[step])


def program_path_callback(program: Optional[Path], ctx: typer.Context) -> Path:
    """
    Callback to determine the compiled program path
    If the program path is not provided, the default program path will be used.
    """
    if program:
        return program
    return get_default_program(ctx.params.get("step", Step.MAIN))


def validate_body_params(
    step: Step, start_index: Optional[int], chunk_size: Optional[int]
) -> None:
    """Validate that body step parameters are provided correctly."""
    if step == Step.BODY:
        if start_index is None or chunk_size is None:
            typer.echo(
                "Error: --start-index and --len parameters are required for body step"
            )
            raise typer.Exit(1)
        if start_index < 0:
            typer.echo("Error: start-index must be non-negative")
            raise typer.Exit(1)
        if chunk_size <= 0:
            typer.echo("Error: len must be positive")
            raise typer.Exit(1)


def validate_mpt_diff_params(branch_index: Optional[int]) -> None:
    """Validate that mpt_diff step parameters are provided correctly."""
    if branch_index is None:
        typer.echo("Error: --branch-index parameter is required for mpt_diff step")
        raise typer.Exit(1)
    if branch_index < 0 or branch_index > 15:
        typer.echo("Error: branch-index must be between 0 and 15")
        raise typer.Exit(1)


def load_program_hashes() -> Dict[str, int]:
    """Load program hashes from the program_hashes.json file."""
    hashes_file = Path("build/program_hashes.json")
    try:
        if not hashes_file.exists():
            console.print(
                f"[yellow]Warning: Program hashes file not found at {hashes_file}[/]"
            )
            return {}

        with open(hashes_file, "r") as f:
            program_hashes = json.load(f)

        console.print(f"[blue]Loaded program hashes from {hashes_file}[/]")
        return program_hashes
    except Exception as e:
        console.print(f"[yellow]Warning: Failed to load program hashes: {e}[/]")
        return {}


def get_step_program_hash(step: Step, program_hashes: Dict[str, int]) -> int:
    """Get the program hash for a given step from the loaded program hashes."""
    compiled_program_path = get_default_program(step)
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


# ============================================================================
# COMMAND IMPLEMENTATIONS
# ============================================================================


@app.command()
def trace(
    block_number: int = typer.Option(
        ..., "-b", "--block", help="Ethereum block number"
    ),
    data_dir: Path = typer.Option(
        Path("data"),
        help="Base data directory",
        dir_okay=True,
        file_okay=False,
    ),
    proving_run_id: Optional[str] = typer.Option(
        None,
        help="Proving run ID (if not provided, will use next available)",
    ),
    trace_path: Path = typer.Option(
        None,
        help="Path to save trace (if not provided, will be determined from data structure)",
        dir_okay=False,
        file_okay=True,
    ),
    chain_id: Optional[int] = typer.Option(
        None,
        help="Chain ID (if not provided, will be read from ZKPI file)",
    ),
    zkpi_version: str = typer.Option(
        "1",
        help="ZKPI version",
    ),
    step: Step = typer.Option(
        Step.MAIN,
        "-s",
        "--step",
        help="Step to run: 'main', 'init', 'body', 'teardown', or 'aggregator'",
    ),
    compiled_program: Path = typer.Option(
        None,
        help="Path to compiled Cairo program",
        exists=True,
        dir_okay=False,
        file_okay=True,
        callback=program_path_callback,
    ),
    start_index: Optional[int] = typer.Option(
        None,
        "--start-index",
        help="Starting transaction index for body step",
    ),
    chunk_size: Optional[int] = typer.Option(
        None,
        "--len",
        help="Number of transactions to process in this chunk for body step",
    ),
    branch_index: Optional[int] = typer.Option(
        None,
        "--branch-index",
        help="Branch index to process (0-15) for mpt_diff step",
    ),
    output_trace_components: bool = typer.Option(
        False,
        "--output-trace-components",
        help="Output trace components",
    ),
    cairo_pie: bool = typer.Option(
        False,
        "--cairo-pie",
        help="Output Cairo PIE file",
    ),
):
    """
    Runs the KETH trace-generation step for a given Ethereum block.
    Serializes generated prover inputs to the specified output directory.
    """
    validate_block_number(block_number)
    StepHandler.validate_step_params(step, start_index, chunk_size, branch_index)

    # Create context with automatic resolution
    ctx = KethContext.create(
        data_dir=data_dir,
        block_number=block_number,
        chain_id=chain_id,
        zkpi_version=zkpi_version,
        proving_run_id=proving_run_id,
    )

    # Determine output path
    if trace_path is None:
        trace_path = ctx.proving_run_dir
    else:
        trace_path.parent.mkdir(parents=True, exist_ok=True)

    output_filename = StepHandler.get_output_filename(
        step, block_number, start_index, chunk_size, branch_index, cairo_pie=cairo_pie
    )
    output_path = trace_path / output_filename

    @handle_command_error("generating trace")
    def _generate_trace():
        program_input = StepHandler.load_program_input(
            step, ctx.zkpi_path, start_index, chunk_size, branch_index
        )

        run_generate_trace(
            entrypoint="main",
            program_input=program_input,
            compiled_program_path=str(compiled_program),
            output_path=output_path,
            output_trace_components=output_trace_components,
            cairo_pie=cairo_pie,
        )
        console.print(f"[green]✓[/] Trace generated successfully in {output_path}")

    with console.status(
        f"[bold green]Generating trace for {step} step of block {block_number}..."
    ):
        _generate_trace()


@app.command()
def prove(
    prover_inputs_path: Path = typer.Option(
        ...,
        help="Path to prover inputs (prover_input_info.json)",
        exists=True,
        dir_okay=False,
        file_okay=True,
    ),
    proof_path: Path = typer.Option(
        None,
        help="Path to save proof (if not provided, will be determined from data structure)",
        dir_okay=False,
        file_okay=True,
    ),
    data_dir: Path = typer.Option(
        Path("data"),
        help="Base data directory",
        dir_okay=True,
        file_okay=False,
    ),
    serde_cairo: bool = typer.Option(
        False,
        "--serde-cairo",
        help="Serialize the proof to a cairo-compatible format",
    ),
):
    """
    Generate a STWO proof from the prover input information file.

    Reads the prover input info generated by the 'trace' command and
    invokes the STWO prover to generate a proof file.
    """
    # If proof_path is not provided, determine it from the input prover_inputs_path
    if proof_path is None:
        prover_run_id = prover_inputs_path.parent.name
        block_number = prover_inputs_path.parent.parent.name
        chain_id = prover_inputs_path.parent.parent.parent.name
        proof_path = (
            get_proving_run_dir(data_dir, chain_id, block_number, prover_run_id)
            / f"proof_{prover_run_id}.json"
        )
    else:
        proof_path.parent.mkdir(parents=True, exist_ok=True)

    @handle_command_error("generating proof")
    def _generate_proof():
        run_prove(
            prover_input_path=prover_inputs_path,
            proof_path=proof_path,
            serde_cairo=serde_cairo,
        )
        console.print(f"[green]✓[/] Proof generated successfully at {proof_path}")

    with console.status("[bold green]Generating proof..."):
        _generate_proof()


@app.command()
def verify(
    proof_path: Path = typer.Option(
        ...,
        help="Path to proof.json",
        exists=True,
        dir_okay=False,
        file_okay=True,
    ),
):
    """
    Run the STWO proof verifier against the specified proof file.

    Args:
        proof_path: Path to the JSON-serialized proof file.
    """

    @handle_command_error("verifying proof")
    def _verify_proof():
        run_verify(proof_path=proof_path)
        console.print("[green]✓[/] Proof verified successfully")

    with console.status("[bold green]Verifying proof..."):
        _verify_proof()


@app.command()
def e2e(
    block_number: int = typer.Option(
        ..., "-b", "--block", help="Ethereum block number"
    ),
    data_dir: Path = typer.Option(
        Path("data"),
        help="Base data directory",
        dir_okay=True,
        file_okay=False,
    ),
    chain_id: Optional[int] = typer.Option(
        None,
        help="Chain ID (if not provided, will be read from ZKPI file)",
    ),
    zkpi_version: str = typer.Option(
        "1",
        help="ZKPI version",
    ),
    proving_run_id: Optional[str] = typer.Option(
        None,
        help="Proving run ID (if not provided, will use next available)",
    ),
    step: Step = typer.Option(
        Step.MAIN,
        "-s",
        "--step",
        help="Step to run: 'main', 'init', 'body', 'teardown', or 'aggregator'",
    ),
    compiled_program: Path = typer.Option(
        None,
        help="Path to compiled Cairo program",
        exists=True,
        dir_okay=False,
        file_okay=True,
        callback=program_path_callback,
    ),
    verify_proof: bool = typer.Option(
        False,
        "--verify",
        help="Verify proof after generation",
    ),
    start_index: Optional[int] = typer.Option(
        None,
        "--start-index",
        help="Starting transaction index for body step",
    ),
    chunk_size: Optional[int] = typer.Option(
        None,
        "--len",
        help="Number of transactions to process in this chunk for body step",
    ),
    branch_index: Optional[int] = typer.Option(
        None,
        "--branch-index",
        help="Branch index to process (0-15) for mpt_diff step",
    ),
    serde_cairo: bool = typer.Option(
        False,
        "--serde-cairo",
        help="Serialize the proof to a cairo-compatible format",
    ),
):
    """
    Run the full end-to-end trace generation, proving and verification flow

    This command combines the 'trace', 'prove', and optionally 'verify' steps
    without writing intermediate trace files to disk.
    """
    validate_block_number(block_number)
    StepHandler.validate_step_params(step, start_index, chunk_size, branch_index)

    # Create context with automatic resolution
    ctx = KethContext.create(
        data_dir=data_dir,
        block_number=block_number,
        chain_id=chain_id,
        zkpi_version=zkpi_version,
        proving_run_id=proving_run_id,
    )

    # Determine proof path
    proof_filename = StepHandler.get_proof_filename(
        step, start_index, chunk_size, branch_index
    )
    proof_path = ctx.proving_run_dir / proof_filename

    @handle_command_error("in pipeline")
    def _run_pipeline():
        program_input = StepHandler.load_program_input(
            step, ctx.zkpi_path, start_index, chunk_size, branch_index
        )

        run_end_to_end(
            "main",
            program_input,
            str(compiled_program),
            proof_path,
            serde_cairo,
            verify_proof,
        )
        console.print("[green]✓[/] Pipeline completed successfully")
        console.print(f"[green]✓[/] Proof written to {proof_path}")
        if verify_proof:
            console.print("[green]✓[/] Proof verified successfully")

    with console.status(
        f"[bold green]Running pipeline for {step} step of block {block_number}..."
    ):
        _run_pipeline()


@app.command()
def generate_ar_inputs(
    block_number: int = typer.Option(
        ..., "-b", "--block", help="Ethereum block number"
    ),
    data_dir: Path = typer.Option(
        Path("data"),
        help="Base data directory",
        dir_okay=True,
        file_okay=False,
    ),
    proving_run_id: Optional[str] = typer.Option(
        None,
        help="Proving run ID (if not provided, will use next available)",
    ),
    chain_id: Optional[int] = typer.Option(
        None,
        help="Chain ID (if not provided, will be read from ZKPI file)",
    ),
    zkpi_version: str = typer.Option(
        "1",
        help="ZKPI version",
    ),
    body_chunk_size: int = typer.Option(
        10,
        "--body-chunk-size",
        help="Number of transactions to process in each body chunk",
    ),
    output_trace_components: bool = typer.Option(
        False,
        "--output-trace-components",
        help="Output trace components",
    ),
    cairo_pie: bool = typer.Option(
        False,
        "--cairo-pie",
        help="Output Cairo PIE files",
    ),
):
    """
    Generate all AR inputs (Automated Recursive inputs for Ethereum) for a block.

    This command generates traces for:
    - init step
    - body steps (chunked by --body-chunk-size transactions)
    - teardown step

    All traces are saved with consistent naming patterns. Supports both prover input
    and Cairo PIE output formats via the --cairo-pie flag.
    """
    validate_block_number(block_number)

    # Create context with automatic resolution
    ctx = KethContext.create(
        data_dir=data_dir,
        block_number=block_number,
        chain_id=chain_id,
        zkpi_version=zkpi_version,
        proving_run_id=proving_run_id,
    )

    # Load ZKPI to get transaction count
    zkpi_program_input = load_zkpi_fixture(ctx.zkpi_path)
    total_transactions = len(zkpi_program_input["block"].transactions)

    console.print(f"[blue]Generating AR inputs for block {block_number}[/]")
    console.print(f"[blue]Total transactions: {total_transactions}[/]")
    console.print(f"[blue]Body chunk size: {body_chunk_size}[/]")

    steps_to_generate = []

    # Step 1: Generate init trace
    steps_to_generate.append(("init", Step.INIT, None, None, None))

    # Step 2: Generate body traces in chunks
    for start_index in range(0, total_transactions, body_chunk_size):
        chunk_size = min(body_chunk_size, total_transactions - start_index)
        steps_to_generate.append(("body", Step.BODY, start_index, chunk_size, None))

    # Step 3: Generate teardown trace
    steps_to_generate.append(("teardown", Step.TEARDOWN, None, None, None))

    # Step 4: Generate mpt_diff traces (16 branches)
    for branch_index in range(16):
        steps_to_generate.append(("mpt_diff", Step.MPT_DIFF, None, None, branch_index))

    # Step 5: Generate aggregator trace
    steps_to_generate.append(("aggregator", Step.AGGREGATOR, None, None, None))

    total_steps = len(steps_to_generate)
    console.print(f"[blue]Total steps to generate: {total_steps}[/]")

    @handle_command_error("generating AR inputs")
    def _generate_all_traces():
        for i, (step_name, step, start_index, chunk_size, branch_index) in enumerate(
            steps_to_generate, 1
        ):
            # Get the appropriate compiled program
            compiled_program = get_default_program(step)

            if not compiled_program.exists():
                console.print(
                    f"[yellow]Warning: Compiled program not found at {compiled_program}[/]"
                )
                console.print(f"[yellow]Skipping {step_name} step[/]")
                continue

            # Generate output filename with consistent naming
            output_filename = StepHandler.get_output_filename(
                step,
                block_number,
                start_index,
                chunk_size,
                branch_index,
                cairo_pie=cairo_pie,
            )
            output_path = ctx.proving_run_dir / output_filename

            # Load program input
            program_input = StepHandler.load_program_input(
                step, ctx.zkpi_path, start_index, chunk_size, branch_index
            )

            step_description = step_name
            if step == Step.BODY:
                step_description = f"body [{start_index}:{start_index + chunk_size}]"
            elif step == Step.MPT_DIFF:
                step_description = f"mpt_diff [branch {branch_index}]"

            with console.status(
                f"[bold green]Generating {step_description} trace ({i}/{total_steps})..."
            ):
                run_generate_trace(
                    entrypoint="main",
                    program_input=program_input,
                    compiled_program_path=str(compiled_program),
                    output_path=output_path,
                    output_trace_components=output_trace_components,
                    cairo_pie=cairo_pie,
                )
                console.print(
                    f"[green]✓[/] {step_description} trace: {output_path.name}"
                )

        console.print(
            f"[green]✓[/] All AR inputs generated successfully in {ctx.proving_run_dir}"
        )

    _generate_all_traces()


if __name__ == "__main__":
    app()

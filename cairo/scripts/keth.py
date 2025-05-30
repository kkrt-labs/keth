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
from typing import Any, Callable, Dict, Optional

import typer
from rich.console import Console
from rich.logging import RichHandler

from cairo_addons.rust_bindings.stwo_bindings import prove as run_prove
from cairo_addons.rust_bindings.stwo_bindings import verify as run_verify
from cairo_addons.rust_bindings.vm import generate_trace as run_generate_trace
from cairo_addons.rust_bindings.vm import run_end_to_end
from utils.fixture_loader import (
    CANCUN_FORK_BLOCK,
    load_body_input,
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


@dataclass
class KethContext:
    """Shared context for Keth operations."""

    data_dir: Path
    chain_id: int
    block_number: int
    zkpi_version: str
    proving_run_id: int
    zkpi_path: Path
    proving_run_dir: Path

    @classmethod
    def create(
        cls,
        data_dir: Path,
        block_number: int,
        chain_id: Optional[int] = None,
        zkpi_version: str = "1",
        proving_run_id: Optional[int] = None,
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
        step: Step, start_index: Optional[int], chunk_size: Optional[int]
    ) -> None:
        """Validate step-specific parameters."""
        if step == Step.BODY:
            validate_body_params(step, start_index, chunk_size)

    @staticmethod
    def load_program_input(
        step: Step,
        zkpi_path: Path,
        start_index: Optional[int] = None,
        chunk_size: Optional[int] = None,
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
            case _:
                return load_zkpi_fixture(zkpi_path)

    @staticmethod
    def get_output_filename(
        step: Step,
        block_number: int,
        start_index: Optional[int] = None,
        chunk_size: Optional[int] = None,
        file_type: str = "prover_input_info",
    ) -> str:
        """Generate output filename based on step and parameters."""
        if step == Step.BODY and start_index is not None and chunk_size is not None:
            return f"{file_type}_{block_number}_body_{start_index}_{chunk_size}.json"
        elif step == Step.INIT:
            return f"{file_type}_{block_number}_init.json"
        elif step == Step.TEARDOWN:
            return f"{file_type}_{block_number}_teardown.json"
        elif step == Step.AGGREGATOR:
            return f"{file_type}_{block_number}_aggregator.json"
        return f"{file_type}_{block_number}.json"

    @staticmethod
    def get_proof_filename(
        step: Step, start_index: Optional[int] = None, chunk_size: Optional[int] = None
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


def get_next_proving_run_id(data_dir: Path, chain_id: int, block_number: int) -> int:
    """Get the next sequential proving run ID for a given chain and block."""
    block_dir = data_dir / str(chain_id) / str(block_number)
    if not block_dir.exists():
        return 1

    # Find existing proving run directories
    existing_runs = []
    for item in block_dir.iterdir():
        if item.is_dir() and item.name.isdigit():
            existing_runs.append(int(item.name))

    return max(existing_runs, default=0) + 1


def get_zkpi_path(
    data_dir: Path, chain_id: int, block_number: int, version: str = "1"
) -> Path:
    """Get the path to the ZKPI file for a given chain, block, and version."""
    return data_dir / str(chain_id) / str(block_number) / f"zkpi_{version}.json"


def get_proving_run_dir(
    data_dir: Path, chain_id: int, block_number: int, proving_run_id: int
) -> Path:
    """Get the proving run directory for a given chain, block, and proving run ID."""
    return data_dir / str(chain_id) / str(block_number) / str(proving_run_id)


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
    """Validate that the block number is after Cancun fork."""
    if block_number < CANCUN_FORK_BLOCK:
        typer.echo(
            f"Error: Block {block_number} is before Cancun fork ({CANCUN_FORK_BLOCK})"
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
    proving_run_id: Optional[int] = typer.Option(
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
    output_trace_components: bool = typer.Option(
        False,
        "--output-trace-components",
        help="Output trace components",
    ),
    pi_json: bool = typer.Option(
        False,
        "--pi-json",
        help="Output prover inputs in JSON format",
    ),
):
    """
    Runs the KETH trace-generation step for a given Ethereum block.
    Serializes generated prover inputs to the specified output directory.
    """
    validate_block_number(block_number)
    StepHandler.validate_step_params(step, start_index, chunk_size)

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
        step, block_number, start_index, chunk_size
    )
    output_path = trace_path / output_filename

    @handle_command_error("generating trace")
    def _generate_trace():
        program_input = StepHandler.load_program_input(
            step, ctx.zkpi_path, start_index, chunk_size
        )

        run_generate_trace(
            entrypoint="main",
            program_input=program_input,
            compiled_program_path=str(compiled_program),
            output_path=output_path,
            output_trace_components=output_trace_components,
            pi_json=pi_json,
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
    proving_run_id: Optional[int] = typer.Option(
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
    StepHandler.validate_step_params(step, start_index, chunk_size)

    # Create context with automatic resolution
    ctx = KethContext.create(
        data_dir=data_dir,
        block_number=block_number,
        chain_id=chain_id,
        zkpi_version=zkpi_version,
        proving_run_id=proving_run_id,
    )

    # Determine proof path
    proof_filename = StepHandler.get_proof_filename(step, start_index, chunk_size)
    proof_path = ctx.proving_run_dir / proof_filename

    @handle_command_error("in pipeline")
    def _run_pipeline():
        program_input = StepHandler.load_program_input(
            step, ctx.zkpi_path, start_index, chunk_size
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
def generate_ar_pies(
    block_number: int = typer.Option(
        ..., "-b", "--block", help="Ethereum block number"
    ),
    data_dir: Path = typer.Option(
        Path("data"),
        help="Base data directory",
        dir_okay=True,
        file_okay=False,
    ),
    proving_run_id: Optional[int] = typer.Option(
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
    pi_json: bool = typer.Option(
        False,
        "--pi-json",
        help="Output prover inputs in JSON format",
    ),
):
    """
    Generate all AR-PIE (Automated Recursive Proof Inputs for Ethereum) traces for a block.

    This command generates traces for:
    - init step
    - body steps (chunked by --body-chunk-size transactions)
    - teardown step

    All traces are saved with consistent naming patterns matching the proof naming convention.
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

    console.print(f"[blue]Generating AR-PIE traces for block {block_number}[/]")
    console.print(f"[blue]Total transactions: {total_transactions}[/]")
    console.print(f"[blue]Body chunk size: {body_chunk_size}[/]")

    steps_to_generate = []

    # Step 1: Generate init trace
    steps_to_generate.append(("init", Step.INIT, None, None))

    # Step 2: Generate body traces in chunks
    for start_index in range(0, total_transactions, body_chunk_size):
        chunk_size = min(body_chunk_size, total_transactions - start_index)
        steps_to_generate.append(("body", Step.BODY, start_index, chunk_size))

    # Step 3: Generate teardown trace
    steps_to_generate.append(("teardown", Step.TEARDOWN, None, None))

    total_steps = len(steps_to_generate)
    console.print(f"[blue]Total steps to generate: {total_steps}[/]")

    @handle_command_error("generating AR-PIE traces")
    def _generate_all_traces():
        for i, (step_name, step, start_index, chunk_size) in enumerate(
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
                step, block_number, start_index, chunk_size
            )
            output_path = ctx.proving_run_dir / output_filename

            # Load program input
            program_input = StepHandler.load_program_input(
                step, ctx.zkpi_path, start_index, chunk_size
            )

            step_description = step_name
            if step == Step.BODY:
                step_description = f"body [{start_index}:{start_index + chunk_size}]"

            with console.status(
                f"[bold green]Generating {step_description} trace ({i}/{total_steps})..."
            ):
                run_generate_trace(
                    entrypoint="main",
                    program_input=program_input,
                    compiled_program_path=str(compiled_program),
                    output_path=output_path,
                    output_trace_components=output_trace_components,
                    pi_json=pi_json,
                )
                console.print(
                    f"[green]✓[/] {step_description} trace: {output_path.name}"
                )

        console.print(
            f"[green]✓[/] All AR-PIE traces generated successfully in {ctx.proving_run_dir}"
        )

    _generate_all_traces()


if __name__ == "__main__":
    app()

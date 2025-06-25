"""Command-line interface for Keth CLI."""

# noqa: F401
import logging
import traceback
from functools import wraps
from pathlib import Path
from typing import Callable, Optional

import typer
from rich.console import Console
from rich.logging import RichHandler

from keth_types.patches import apply_patches

from .config import KethConfig
from .core import KethContext, validate_block_number
from .exceptions import (
    CompiledProgramNotFoundError,
    InvalidBlockNumberError,
    InvalidBranchIndexError,
    InvalidStepParametersError,
    KethError,
    MissingSegmentOutputError,
    ZkpiFileNotFoundError,
)
from .orchestration import (
    run_ar_inputs_pipeline,
    run_e2e_pipeline,
    run_prove_pipeline,
    run_trace_pipeline,
    run_verify_pipeline,
)
from .steps import Step, StepHandler

apply_patches()

# Setup logging
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


def handle_command_error(operation: str) -> Callable:
    """Decorator to handle common command errors."""

    def decorator(func: Callable) -> Callable:
        @wraps(func)
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


def program_path_callback(program: Optional[Path], ctx: typer.Context) -> Path:
    """
    Callback to determine the compiled program path.
    If the program path is not provided, the default program path will be used.
    """
    if program:
        return program
    config = KethConfig()
    step = Step(ctx.params.get("step", Step.MAIN))
    return StepHandler.get_default_program(step, config)


@app.command()
def trace(
    block_number: int = typer.Option(
        ..., "-b", "--block", help="Ethereum block number"
    ),
    data_dir: Path = typer.Option(
        KethConfig.DEFAULT_DATA_DIR,
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
        KethConfig.DEFAULT_ZKPI_VERSION,
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
    try:
        config = KethConfig()
        validate_block_number(block_number, config)

        # Create context
        ctx = KethContext.create(
            config=config,
            data_dir=data_dir,
            block_number=block_number,
            chain_id=chain_id,
            zkpi_version=zkpi_version,
            proving_run_id=proving_run_id,
        )

        # Run trace pipeline
        run_trace_pipeline(
            ctx=ctx,
            step=step,
            compiled_program=compiled_program,
            trace_path=trace_path,
            start_index=start_index,
            chunk_size=chunk_size,
            branch_index=branch_index,
            output_trace_components=output_trace_components,
            cairo_pie=cairo_pie,
        )

    except InvalidBlockNumberError as e:
        console.print(f"[red]Error: {e}[/]")
        raise typer.Exit(1)
    except ZkpiFileNotFoundError as e:
        console.print(f"[red]Error: {e}[/]")
        raise typer.Exit(1)
    except InvalidStepParametersError as e:
        console.print(f"[red]Error: {e}[/]")
        raise typer.Exit(1)
    except InvalidBranchIndexError as e:
        console.print(f"[red]Error: {e}[/]")
        raise typer.Exit(1)
    except KethError as e:
        console.print(f"[red]Error: {e}[/]")
        raise typer.Exit(1)
    except Exception as e:
        console.print(f"[red]Error in pipeline: {e}[/]")
        logger.exception("Unexpected error")
        raise typer.Exit(1)


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
        KethConfig.DEFAULT_DATA_DIR,
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
    try:
        run_prove_pipeline(
            prover_inputs_path=prover_inputs_path,
            proof_path=proof_path,
            data_dir=data_dir,
            serde_cairo=serde_cairo,
        )
    except KethError as e:
        console.print(f"[red]Error: {e}[/]")
        raise typer.Exit(1)
    except Exception as e:
        console.print(f"[red]Error generating proof: {e}[/]")
        logger.exception("Unexpected error")
        raise typer.Exit(1)


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
    try:
        run_verify_pipeline(proof_path=proof_path)
    except KethError as e:
        console.print(f"[red]Error: {e}[/]")
        raise typer.Exit(1)
    except Exception as e:
        console.print(f"[red]Error verifying proof: {e}[/]")
        logger.exception("Unexpected error")
        raise typer.Exit(1)


@app.command()
def e2e(
    block_number: int = typer.Option(
        ..., "-b", "--block", help="Ethereum block number"
    ),
    data_dir: Path = typer.Option(
        KethConfig.DEFAULT_DATA_DIR,
        help="Base data directory",
        dir_okay=True,
        file_okay=False,
    ),
    chain_id: Optional[int] = typer.Option(
        None,
        help="Chain ID (if not provided, will be read from ZKPI file)",
    ),
    zkpi_version: str = typer.Option(
        KethConfig.DEFAULT_ZKPI_VERSION,
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
    try:
        config = KethConfig()
        validate_block_number(block_number, config)

        # Create context
        ctx = KethContext.create(
            config=config,
            data_dir=data_dir,
            block_number=block_number,
            chain_id=chain_id,
            zkpi_version=zkpi_version,
            proving_run_id=proving_run_id,
        )

        # Run e2e pipeline
        run_e2e_pipeline(
            ctx=ctx,
            step=step,
            compiled_program=compiled_program,
            start_index=start_index,
            chunk_size=chunk_size,
            branch_index=branch_index,
            verify_proof=verify_proof,
            serde_cairo=serde_cairo,
        )

    except InvalidBlockNumberError as e:
        console.print(f"[red]Error: {e}[/]")
        raise typer.Exit(1)
    except ZkpiFileNotFoundError as e:
        console.print(f"[red]Error: {e}[/]")
        raise typer.Exit(1)
    except InvalidStepParametersError as e:
        console.print(f"[red]Error: {e}[/]")
        raise typer.Exit(1)
    except InvalidBranchIndexError as e:
        console.print(f"[red]Error: {e}[/]")
        raise typer.Exit(1)
    except KethError as e:
        console.print(f"[red]Error: {e}[/]")
        raise typer.Exit(1)
    except Exception as e:
        console.print(f"[red]Error in pipeline: {e}[/]")
        logger.exception("Unexpected error")
        raise typer.Exit(1)


@app.command()
def generate_ar_inputs(
    block_number: int = typer.Option(
        ..., "-b", "--block", help="Ethereum block number"
    ),
    data_dir: Path = typer.Option(
        KethConfig.DEFAULT_DATA_DIR,
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
        KethConfig.DEFAULT_ZKPI_VERSION,
        help="ZKPI version",
    ),
    body_chunk_size: int = typer.Option(
        KethConfig.DEFAULT_BODY_CHUNK_SIZE,
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
    try:
        config = KethConfig()
        validate_block_number(block_number, config)

        # Create context
        ctx = KethContext.create(
            config=config,
            data_dir=data_dir,
            block_number=block_number,
            chain_id=chain_id,
            zkpi_version=zkpi_version,
            proving_run_id=proving_run_id,
        )

        # Run AR inputs pipeline
        run_ar_inputs_pipeline(
            ctx=ctx,
            body_chunk_size=body_chunk_size,
            output_trace_components=output_trace_components,
            cairo_pie=cairo_pie,
        )

    except InvalidBlockNumberError as e:
        console.print(f"[red]Error: {e}[/]")
        raise typer.Exit(1)
    except ZkpiFileNotFoundError as e:
        console.print(f"[red]Error: {e}[/]")
        raise typer.Exit(1)
    except CompiledProgramNotFoundError as e:
        console.print(f"[red]Error: {e}[/]")
        raise typer.Exit(1)
    except MissingSegmentOutputError as e:
        console.print(f"[red]Error: {e}[/]")
        raise typer.Exit(1)
    except KethError as e:
        console.print(f"[red]Error: {e}[/]")
        raise typer.Exit(1)
    except Exception as e:
        console.print(f"[red]Error generating AR inputs: {e}[/]")
        logger.exception("Unexpected error")
        raise typer.Exit(1)


if __name__ == "__main__":
    app()

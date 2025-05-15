"""
Keth CLI - A tool for generating execution traces and proofs for Ethereum blocks using STWO.

This CLI provides four main commands:
- trace: Generates the execution trace and serializes it as prover inputs from a block's ZK-PI
- prove: Generates a proof from the prover inputs
- verify: Verifies a proof
- e2e: Runs the full trace-generation, proving and verification pipeline
"""

import logging
import traceback
from enum import Enum
from pathlib import Path
from typing import Optional

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


# Typer does not support Literal["main", "init"] in its type enforcement, so we use an Enum instead.
# See <https://typer.tiangolo.com/tutorial/parameter-types/enum/?h=enum>
class Step(str, Enum):
    MAIN = "main"
    INIT = "init"
    BODY = "body"
    TEARDOWN = "teardown"


def validate_block_number(block_number: int) -> None:
    """Validate that the block number is after prague fork."""
    if block_number < PRAGUE_FORK_BLOCK:
        typer.echo(
            f"Error: Block {block_number} is before prague fork ({PRAGUE_FORK_BLOCK})"
        )
        raise typer.Exit(1)


def get_default_program(step: Step) -> Path:
    """Returns the default compiled program path based on step"""
    step_to_program = {
        Step.MAIN: "build/main_compiled.json",
        Step.INIT: "build/init_compiled.json",
        Step.BODY: "build/body_compiled.json",
        Step.TEARDOWN: "build/teardown_compiled.json",
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


@app.command()
def trace(
    block_number: int = typer.Option(
        ..., "-b", "--block", help="Ethereum block number"
    ),
    output_dir: Path = typer.Option(
        Path("output"),
        help="Directory to save trace artifacts (prover inputs)",
        dir_okay=True,
        file_okay=False,
    ),
    data_dir: Path = typer.Option(
        Path("data/1/inputs"),
        help="Directory containing prover inputs (ZK-PI)",
        dir_okay=True,
        file_okay=False,
    ),
    step: Step = typer.Option(
        Step.MAIN,
        "-s",
        "--step",
        help="Step to run: 'main' or 'init'",
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

    Args:
        block_number: The Ethereum block number to generate a trace for.
        output_dir: The directory to save the trace artifacts to.
        data_dir: The directory containing the ZK-PI fixture for that block.
        step: The step to run: 'main' or 'init'.
        compiled_program: The path to the compiled KETH Cairo program.
        start_index: The starting transaction index for the body step.
        chunk_size: The number of transactions to process in this chunk for the body step.
    """
    validate_block_number(block_number)
    # For body step, include chunk info in the proof filename
    if step == Step.BODY:
        output_path = (
            output_dir
            / f"prover_input_info_{block_number}_{start_index}_{chunk_size}.json"
        )
    else:
        output_path = output_dir / f"prover_input_info_{block_number}.json"

    with console.status(
        f"[bold green]Generating trace for {step} step of block {block_number}..."
    ):
        try:
            zkpi_path = data_dir / f"{block_number}.json"
            # Add chunk parameters for body step
            match step:
                case Step.BODY:
                    program_input = load_body_input(
                        zkpi_path=zkpi_path,
                        start_index=start_index,
                        chunk_size=chunk_size,
                    )
                case Step.TEARDOWN:
                    program_input = load_teardown_input(zkpi_path)
                case _:
                    program_input = load_zkpi_fixture(zkpi_path)

            run_generate_trace(
                entrypoint="main",
                program_input=program_input,
                compiled_program_path=str(compiled_program),
                output_path=output_path,
                output_trace_components=output_trace_components,
                pi_json=pi_json,
            )
            console.print(f"[green]✓[/] Trace generated successfully in {output_path}")
        except Exception:
            console.print(
                f"[red]Error generating trace:[/] {str(traceback.format_exc())}"
            )
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
        Path("output/proof.json"),
        help="Directory to save proof to",
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
    proof_path.parent.mkdir(parents=True, exist_ok=True)

    with console.status("[bold green]Generating proof..."):
        try:
            run_prove(
                prover_input_path=prover_inputs_path,
                proof_path=proof_path,
                serde_cairo=serde_cairo,
            )
            console.print(f"[green]✓[/] Proof generated successfully at {proof_path}")
        except Exception:
            import traceback

            console.print(
                f"[red]Error generating proof:[/] {str(traceback.format_exc())}"
            )
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
    with console.status("[bold green]Verifying proof..."):
        try:
            run_verify(proof_path=proof_path)
            console.print("[green]✓[/] Proof verified successfully")
        except Exception:
            console.print(
                f"[red]Error verifying proof:[/] {str(traceback.format_exc())}"
            )
            raise typer.Exit(1)


@app.command()
def e2e(
    block_number: int = typer.Option(
        ..., "-b", "--block", help="Ethereum block number"
    ),
    proof_path: Path = typer.Option(
        Path("output/proof.json"),
        help="Path to save proof",
        dir_okay=False,
        file_okay=True,
    ),
    data_dir: Path = typer.Option(
        Path("data/1/inputs"),
        help="Directory containing prover inputs (ZK-PI)",
        dir_okay=True,
        file_okay=False,
    ),
    step: Step = typer.Option(
        Step.MAIN,
        "-s",
        "--step",
        help="Step to run: 'main', 'init', or 'body'",
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
    without writing intermediate trace files to disk. It reads the ZK-PI fixture,
    runs the Cairo VM, generates the prover input, creates the STWO proof, and
    optionally verifies it. The final proof is saved to the specified path.

    For the body step, you must specify:
    - start-index: The starting transaction index
    - len: Number of transactions to process in this chunk

    The proof will include a commitment hash of the state transition that can be
    verified in the aggregator.
    """
    validate_block_number(block_number)
    validate_body_params(step, start_index, chunk_size)
    proof_path.parent.mkdir(parents=True, exist_ok=True)

    # For body step, include chunk info in the proof filename
    if step == Step.BODY:
        proof_path = (
            proof_path.parent
            / f"proof_body_{block_number}_{start_index}_{chunk_size}.json"
        )

    with console.status(
        f"[bold green]Running pipeline for {step} step of block {block_number}..."
    ):
        try:
            zkpi_path = data_dir / f"{block_number}.json"

            # Add chunk parameters for body step
            match step:
                case Step.BODY:
                    program_input = load_body_input(
                        zkpi_path=zkpi_path,
                        start_index=start_index,
                        chunk_size=chunk_size,
                    )
                case Step.TEARDOWN:
                    program_input = load_teardown_input(zkpi_path)
                case _:
                    program_input = load_zkpi_fixture(zkpi_path)

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
        except Exception:
            console.print(f"[red]Error in pipeline:[/] {str(traceback.format_exc())}")
            raise typer.Exit(1)


if __name__ == "__main__":
    app()

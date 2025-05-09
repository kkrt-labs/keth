#!/usr/bin/env python3
"""
Prove Cairo - A tool for running and proving arbitrary Cairo programs and generating proofs with STWO.

This CLI provides a simple way to run a compiled Cairo program, generate a proof,
and verify the proof using the STWO prover and verifier.
"""

import logging
from pathlib import Path

import typer
from rich.console import Console
from rich.logging import RichHandler

from cairo_addons.rust_bindings.stwo_bindings import prove as run_prove
from cairo_addons.rust_bindings.stwo_bindings import verify as run_verify
from cairo_addons.rust_bindings.vm import generate_trace as run_generate_trace

logging.basicConfig(
    level=logging.INFO,
    format="%(message)s",
    datefmt="[%X]",
    handlers=[RichHandler(rich_tracebacks=True)],
)
logger = logging.getLogger("prove_cairo")
console = Console()

app = typer.Typer(
    help="Prove Cairo - Run and prove arbitrary Cairo programs. Set LOG_FORMAT=[plain|json] to control Rust log output.",
    no_args_is_help=True,
)


@app.command()
def run_and_prove(
    compiled_program: Path = typer.Option(
        ...,
        help="Path to compiled Cairo program",
        exists=True,
        dir_okay=False,
        file_okay=True,
    ),
    entrypoint: str = typer.Option(
        "main",
        help="Entrypoint function name to run",
    ),
    arguments: str = typer.Option(
        "",
        help="Serialized arguments as comma-separated felts",
    ),
    output_dir: Path = typer.Option(
        Path("output"),
        help="Directory to save trace artifacts and proof",
        dir_okay=True,
        file_okay=False,
    ),
    serde_cairo: bool = typer.Option(
        False,
        "--serde-cairo",
        help="Serialize the proof to a cairo-compatible format",
    ),
    verify_proof: bool = typer.Option(
        False,
        "--verify",
        help="Verify proof after generation",
    ),
    output_trace_components: bool = typer.Option(
        False,
        "--output-trace-components",
        help="Output trace components",
    ),
    pi_json: bool = typer.Option(
        False,
        "--pi-json",
        help="Serialize the prover inputs to a JSON format",
    ),
):
    """
    Run a compiled Cairo program, generate a proof, and optionally verify it.

    This command takes a compiled Cairo program, runs it with the specified entrypoint
    and arguments, generates a proof using STWO, and saves the artifacts to the output directory.
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    program_name = compiled_program.stem
    trace_output_path = output_dir / f"prover_input_info_{program_name}.json"
    proof_path = output_dir / f"proof_{program_name}.json"

    with console.status(f"[bold green]Processing {program_name}..."):
        try:
            # Parse arguments if provided
            program_input = []
            if arguments:
                program_input = [
                    int(arg.strip()) for arg in arguments.split(",") if arg.strip()
                ]

            # Step 1: Generate trace
            console.print("[blue]Generating trace...[/]")
            run_generate_trace(
                entrypoint=entrypoint,
                program_input=program_input,
                compiled_program_path=str(compiled_program),
                output_path=trace_output_path,
                output_trace_components=output_trace_components,
                pi_json=pi_json,
            )
            console.print(
                f"[green]✓[/] Trace generated successfully in {trace_output_path}"
            )

            # Step 2: Generate proof
            console.print("[blue]Generating proof...[/]")
            run_prove(
                prover_input_path=trace_output_path,
                proof_path=proof_path,
                serde_cairo=serde_cairo,
            )
            console.print(f"[green]✓[/] Proof generated successfully at {proof_path}")

            # Step 3: Verify proof if requested
            if verify_proof:
                console.print("[blue]Verifying proof...[/]")
                run_verify(proof_path=proof_path)
                console.print("[green]✓[/] Proof verified successfully")

        except Exception as e:
            console.print(f"[red]Error processing program:[/] {str(e)}")
            raise typer.Exit(1)


if __name__ == "__main__":
    app()

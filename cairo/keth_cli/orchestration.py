"""High-level orchestration functions for Keth CLI commands."""

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from rich.console import Console

from cairo_addons.rust_bindings.stwo_bindings import prove as run_prove
from cairo_addons.rust_bindings.stwo_bindings import verify as run_verify
from cairo_addons.rust_bindings.vm import generate_trace as run_generate_trace
from cairo_addons.rust_bindings.vm import run_end_to_end
from utils.fixture_loader import load_zkpi_fixture

from .core import KethContext
from .steps import Step, StepHandler

console = Console()


@dataclass
class TraceJob:
    """Represents a trace generation job."""

    step_name: str
    step: Step
    start_index: Optional[int]
    chunk_size: Optional[int]
    branch_index: Optional[int]
    output_path: Path
    compiled_program: Path
    program_input: Dict[str, Any]


def run_trace_pipeline(
    ctx: KethContext,
    step: Step,
    compiled_program: Path,
    trace_path: Optional[Path],
    start_index: Optional[int],
    chunk_size: Optional[int],
    branch_index: Optional[int],
    output_trace_components: bool,
    cairo_pie: bool,
) -> None:
    """Run the trace generation pipeline."""
    # Validate step parameters
    StepHandler.validate_step_params(step, start_index, chunk_size, branch_index)

    # Determine output path
    if trace_path is None:
        trace_path = ctx.proving_run_dir
    else:
        trace_path.parent.mkdir(parents=True, exist_ok=True)

    output_filename = StepHandler.get_output_filename(
        step,
        ctx.block_number,
        ctx.config,
        start_index,
        chunk_size,
        branch_index,
        cairo_pie=cairo_pie,
    )
    output_path = trace_path / output_filename

    # Load program input
    with console.status(
        f"[bold green]Loading program input for {step} step of block {ctx.block_number}..."
    ):
        program_input = StepHandler.load_program_input(
            step, ctx.zkpi_path, ctx.config, start_index, chunk_size, branch_index
        )

    # Generate trace
    with console.status(
        f"[bold green]Generating trace for {step} step of block {ctx.block_number}..."
    ):
        run_generate_trace(
            entrypoint="main",
            program_input=program_input,
            compiled_program_path=str(compiled_program),
            output_path=output_path,
            output_trace_components=output_trace_components,
            cairo_pie=cairo_pie,
        )
        console.print(f"[green]✓[/] Trace generated successfully in {output_path}")


def run_prove_pipeline(
    prover_inputs_path: Path,
    proof_path: Optional[Path],
    data_dir: Path,
    serde_cairo: bool,
) -> None:
    """Run the proof generation pipeline."""
    # If proof_path is not provided, determine it from the input prover_inputs_path
    if proof_path is None:
        prover_run_id = prover_inputs_path.parent.name
        block_number = prover_inputs_path.parent.parent.name
        chain_id = prover_inputs_path.parent.parent.parent.name
        proof_path = (
            data_dir
            / chain_id
            / block_number
            / prover_run_id
            / f"proof_{prover_run_id}.json"
        )
    else:
        proof_path.parent.mkdir(parents=True, exist_ok=True)

    # Generate proof
    with console.status("[bold green]Generating proof..."):
        run_prove(
            prover_input_path=prover_inputs_path,
            proof_path=proof_path,
            serde_cairo=serde_cairo,
        )
        console.print(f"[green]✓[/] Proof generated successfully at {proof_path}")


def run_verify_pipeline(proof_path: Path) -> None:
    """Run the proof verification pipeline."""
    with console.status("[bold green]Verifying proof..."):
        run_verify(proof_path=proof_path)
        console.print("[green]✓[/] Proof verified successfully")


def run_e2e_pipeline(
    ctx: KethContext,
    step: Step,
    compiled_program: Path,
    start_index: Optional[int],
    chunk_size: Optional[int],
    branch_index: Optional[int],
    verify_proof: bool,
    serde_cairo: bool,
) -> None:
    """Run the end-to-end pipeline."""
    # Validate step parameters
    StepHandler.validate_step_params(step, start_index, chunk_size, branch_index)

    # Determine proof path
    proof_filename = StepHandler.get_proof_filename(
        step, ctx.config, start_index, chunk_size, branch_index
    )
    proof_path = ctx.proving_run_dir / proof_filename

    with console.status(
        f"[bold green]Loading program input for {step} step of block {ctx.block_number}..."
    ):
        # Load program input
        program_input = StepHandler.load_program_input(
            step, ctx.zkpi_path, ctx.config, start_index, chunk_size, branch_index
        )

    # Run end-to-end
    with console.status(
        f"[bold green]Running pipeline for {step} step of block {ctx.block_number}..."
    ):
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


def run_ar_inputs_pipeline(
    ctx: KethContext,
    body_chunk_size: int,
    output_trace_components: bool,
    cairo_pie: bool,
) -> None:
    """Run the AR inputs generation pipeline sequentially."""
    # Load ZKPI to get transaction count
    zkpi_program_input = load_zkpi_fixture(ctx.zkpi_path)
    total_transactions = len(zkpi_program_input["block"].transactions)

    console.print(f"[blue]Generating AR inputs for block {ctx.block_number}[/]")
    console.print(f"[blue]Total transactions: {total_transactions}[/]")
    console.print(f"[blue]Body chunk size: {body_chunk_size}[/]")

    # Build list of steps to generate
    steps_to_generate: List[
        Tuple[str, Step, Optional[int], Optional[int], Optional[int]]
    ] = []

    # Step 1: Generate init trace
    steps_to_generate.append(("init", Step.INIT, None, None, None))

    # Step 2: Generate body traces in chunks
    for start_index in range(0, total_transactions, body_chunk_size):
        chunk_size = min(body_chunk_size, total_transactions - start_index)
        steps_to_generate.append(("body", Step.BODY, start_index, chunk_size, None))

    # Step 3: Generate teardown trace
    steps_to_generate.append(("teardown", Step.TEARDOWN, None, None, None))

    # Step 4: Generate mpt_diff traces (16 branches)
    for branch_index in range(ctx.config.MPT_DIFF_BRANCHES):
        steps_to_generate.append(("mpt_diff", Step.MPT_DIFF, None, None, branch_index))

    # Step 5: Generate aggregator trace
    steps_to_generate.append(("aggregator", Step.AGGREGATOR, None, None, None))

    total_steps = len(steps_to_generate)
    console.print(f"[blue]Total steps to generate: {total_steps}[/]")

    # Use sequential generation to avoid pickling issues
    _generate_traces_sequentially(
        ctx,
        steps_to_generate,
        output_trace_components,
        cairo_pie,
    )


def _generate_traces_sequentially(
    ctx: KethContext,
    steps_to_generate: List[
        Tuple[str, Step, Optional[int], Optional[int], Optional[int]]
    ],
    output_trace_components: bool,
    cairo_pie: bool,
) -> None:
    """Generate traces sequentially."""
    total_steps = len(steps_to_generate)

    for i, (step_name, step, start_index, chunk_size, branch_index) in enumerate(
        steps_to_generate, 1
    ):
        # Get the appropriate compiled program
        compiled_program = StepHandler.get_default_program(step, ctx.config)

        if not compiled_program.exists():
            console.print(
                f"[yellow]Warning: Compiled program not found at {compiled_program}[/]"
            )
            console.print(f"[yellow]Skipping {step_name} step[/]")
            continue

        # Generate output filename with consistent naming
        output_filename = StepHandler.get_output_filename(
            step,
            ctx.block_number,
            ctx.config,
            start_index,
            chunk_size,
            branch_index,
            cairo_pie=cairo_pie,
        )
        output_path = ctx.proving_run_dir / output_filename

        # Load program input
        program_input = StepHandler.load_program_input(
            step, ctx.zkpi_path, ctx.config, start_index, chunk_size, branch_index
        )

        step_description = step_name
        if step == Step.BODY:
            step_description = f"body [{start_index}:{start_index + chunk_size}]"
        elif step == Step.MPT_DIFF:
            step_description = f"mpt_diff branch {branch_index}"

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
            console.print(f"[green]✓[/] {step_description} trace: {output_path.name}")

    console.print(
        f"[green]✓[/] All AR inputs generated successfully in {ctx.proving_run_dir}"
    )

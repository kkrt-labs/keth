"""
Cairo Test System - Runtime and Type Integration

This module handles the execution of Cairo programs and provides the core integration
with the type system for testing. It enables running tests with inputs passed as pure Python by automatically
handling type conversion between Python and Cairo.

The runner works with args_gen.py and serde.py for automatic type conversion.
"""

import json
import logging
from pathlib import Path
from typing import List, Optional, Tuple

import polars as pl
import pytest
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME
from starkware.cairo.lang.compiler.program import Program

from cairo_addons.testing.coverage import coverage_from_trace
from cairo_addons.testing.runner import run_python_vm, run_rust_vm
from cairo_addons.vm import Program as RustProgram
from tests.utils.hints import get_op

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger()


@pytest.fixture(scope="module")
def cairo_files(request) -> List[Path]:
    return request.session.cairo_files[request.node.fspath]


@pytest.fixture(scope="module")
def cairo_programs(request) -> List[Program]:
    return request.session.cairo_programs[request.node.fspath]


@pytest.fixture(scope="module")
def cairo_program(request) -> Program:
    """Returns the first cairo program in the session.
    If there is both a src.cairo and a test_src.cairo program, returns the src program (always compiled first).
    Otherwise, returns the test program.
    """
    return request.session.cairo_programs[request.node.fspath][0]


@pytest.fixture(scope="module")
def line_to_pc_dfs(request) -> List[pl.DataFrame]:
    return request.session.line_to_pc_df[request.node.fspath]


@pytest.fixture(scope="module")
def main_paths(request) -> List[Tuple[str, ...]]:
    return request.session.main_paths[request.node.fspath]


@pytest.fixture(scope="module")
def python_vm(request):
    return (
        request.node.get_closest_marker("python_vm")
        # The Rust VM currently only supports the default prime
        # see https://github.com/lambdaclass/cairo-vm/issues/1910
        or request.config.getoption("prime") != DEFAULT_PRIME
    )


@pytest.fixture(scope="module")
def rust_programs(cairo_programs: List[Program], python_vm: bool) -> List[RustProgram]:
    if python_vm:
        return []

    return [
        RustProgram.from_bytes(
            json.dumps(cairo_program.Schema().dump(cairo_program)).encode()
        )
        for cairo_program in cairo_programs
    ]


@pytest.fixture(scope="module")
def coverage(
    request, cairo_files: List[Path], cairo_programs: List[Program], worker_id: str
):
    """
    Fixture to collect and aggregate coverage from all test runs for each Cairo file.

    Args:
        request: Pytest request object for accessing config and node info.
        cairo_files: List of Cairo file paths associated with the test session.
        worker_id: Unique identifier for the worker in parallel test runs.

    Yields:
        A function that collects coverage for a single test run.

    After yielding, it aggregates all collected reports and dumps them as JSON files.
    """
    # Store coverage reports for each run
    reports: List[pl.DataFrame] = []

    def _collect_coverage(
        cairo_file: Path,
        line_to_pc_df: pl.DataFrame,
        trace: pl.DataFrame,
    ) -> Optional[pl.DataFrame]:
        """
        Collect coverage for a single test run and append it to the reports list.

        Args:
            cairo_program: Compiled Cairo program.
            cairo_file: Path to the Cairo source file.
            trace: DataFrame containing the execution trace.
            program_base: Base address of the program in memory (default: PROGRAM_BASE).

        Returns:
            The coverage DataFrame for this run, or None if debug info is missing.
        """
        coverage_df = coverage_from_trace(str(cairo_file), line_to_pc_df, trace)
        reports.append(coverage_df)
        return coverage_df

    yield _collect_coverage

    # Skip processing if no reports were collected (e.g., all tests failed early)
    if not reports:
        logger.info("No coverage reports collected, skipping aggregation.")
        return

    # Aggregate coverage for each Cairo file
    for cairo_file, cairo_program in zip(cairo_files, cairo_programs):
        # Get all possible statements (lines) from the program's debug info
        all_statements = (
            pl.DataFrame(
                [
                    {
                        "line_number": i,
                        "filename": instruction.inst.input_file.filename,
                    }
                    for instruction in cairo_program.debug_info.instruction_locations.values()
                    # Filter out global scope (e.g., dw instructions)
                    if len(instruction.accessible_scopes) > 1
                    for i in range(
                        instruction.inst.start_line, instruction.inst.end_line + 1
                    )
                ]
            )
            .lazy()
            .with_columns(
                filename=(
                    pl.when(pl.col("filename") == "")
                    .then(pl.lit(str(cairo_file)))
                    .otherwise(pl.col("filename"))
                )
            )
        )

        # Concatenate all reports and merge with all statements
        all_coverages = (
            pl.concat([all_statements, pl.concat(reports).lazy()])
            .filter(
                ~pl.col("filename").str.contains(".venv")
            )  # Exclude virtual env files
            .filter(~pl.col("filename").str.contains("test_"))  # Exclude test files
            .collect()
        )

        # Filter for the current Cairo file and prepare missed lines report
        missed = (
            all_coverages.filter(pl.col("filename") == str(cairo_file))
            .with_columns(pl.col("filename").str.replace(str(Path.cwd()) + "/", ""))
            .sort("line_number", descending=False)
            .with_columns(
                pl.col("filename") + ":" + pl.col("line_number").cast(pl.String)
            )
            .drop("line_number")
        )

        # Log coverage results
        with pl.Config(tbl_rows=100, fmt_str_lengths=90):
            if missed.height > 0:
                logger.info(f"Missed lines in {cairo_file}:\n{missed}")
            else:
                logger.info(f"{cairo_file}: 100% coverage ✅")

        # Convert to dictionary for JSON dumping
        coverage_dict = all_coverages.to_dict(as_series=False)
        coverage_data = {
            "coverage": {
                f"{filename}:{line_number}": True
                for filename, line_number in zip(
                    coverage_dict["filename"], coverage_dict["line_number"]
                )
            }
        }

        # Dump coverage to a JSON file
        dump_path = (
            Path("coverage")
            / worker_id
            / cairo_file.relative_to(Path.cwd()).with_suffix(".json")
        )
        dump_path.parent.mkdir(parents=True, exist_ok=True)
        logger.info(f"Dumping coverage to {dump_path}")
        with open(dump_path, "w") as f:
            json.dump(coverage_data, f, indent=4)


@pytest.fixture(scope="module")
def cairo_run_py(
    request,
    cairo_programs,
    cairo_files,
    main_paths,
    line_to_pc_dfs,
    coverage,
):
    """Run the cairo program using Python VM."""
    return run_python_vm(
        cairo_programs,
        cairo_files,
        main_paths,
        line_to_pc_dfs,
        request,
        hint_locals={"get_op": get_op},
        coverage=coverage,
    )


@pytest.fixture(scope="module")
def cairo_run(
    request,
    cairo_programs,
    rust_programs,
    cairo_files,
    main_paths,
    line_to_pc_dfs,
    coverage,
    python_vm,
):
    """
    Run the cairo program corresponding to the python test file at a given entrypoint with given program inputs as kwargs.
    Returns the output of the cairo program put in the output memory segment.

    When --profile-cairo is passed, the cairo program is run with the tracer enabled and the resulting trace is dumped.

    Logic is mainly taken from starkware.cairo.lang.vm.cairo_run with minor updates, mainly builtins discovery from implicit args.

    Type conversion between Python and Cairo is handled by:
    - gen_arg: Converts Python arguments to Cairo memory layout when preparing runner inputs
    - serde: Converts Cairo memory data to Python types by reading into the segments, used to return python types.

    The VM used for the run depends on the presence of a "python_vm" marker in the test.

    Returns:
        The function's return value, converted back to Python types
    """
    if python_vm:
        return run_python_vm(
            cairo_programs,
            cairo_files,
            main_paths,
            line_to_pc_dfs,
            request,
            coverage=coverage,
            hint_locals={"get_op": get_op},
        )

    return run_rust_vm(
        cairo_programs,
        rust_programs,
        cairo_files,
        main_paths,
        line_to_pc_dfs,
        request,
        coverage=coverage,
    )

"""
Cairo Test System - Runtime and Type Integration

This module handles the execution of Cairo programs and provides the core integration
with the type system for testing. It enables running tests with inputs passed as pure Python by automatically
handling type conversion between Python and Cairo.

The runner works with args_gen.py and serde.py for automatic type conversion.
"""

import json
import logging
import pickle
import shutil  # For cleaning up temporary directory
import uuid  # For unique filenames
from pathlib import Path
from typing import List, Tuple

import polars as pl
import pytest
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME
from starkware.cairo.lang.compiler.program import Program

from cairo_addons.rust_bindings.vm import Program as RustProgram
from cairo_addons.testing.caching import get_dump_path
from cairo_addons.testing.coverage import coverage_from_trace
from cairo_addons.testing.runner import run_python_vm, run_rust_vm
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
    Pytest fixture to collect and aggregate coverage across test runs within a module.

    This fixture addresses memory issues associated with collecting coverage for many
    tests within a single module (test file). Instead of accumulating coverage
    DataFrames in memory on each test run, it performs the following steps:
    1. Creates a unique temporary directory for the current worker and test module.
    2. Yields a `_collect_coverage` function to the test runner.
    3. The `_collect_coverage` function calculates coverage for a single test run
       and writes the resulting DataFrame to a unique Parquet file in the temporary
       directory.
    4. After all tests in the module have run, the fixture's teardown logic executes.
    5. It scans all the temporary Parquet files (lazily) using Polars.
    6. It concatenates these lazy frames.
    7. It merges the concatenated coverage data with the base statement information
       for each relevant Cairo file, aggregates the counts, and calculates coverage.
    8. The final aggregated coverage report is written to a JSON file in the
       `coverage/<worker_id>/` directory.
    9. The temporary directory and its Parquet files are deleted.

    This approach significantly reduces peak memory usage during test execution by
    offloading intermediate results to disk, only loading and processing the full
    aggregated data during the final teardown phase of the module.

    Args:
        request: Pytest request object.
        cairo_files: List of Cairo file paths for the session.
        cairo_programs: List of compiled Cairo programs for the session.
        worker_id: ID of the current pytest-xdist worker.

    Yields:
        Callable: The `_collect_coverage` function.
    """
    # Define path for temporary report files for this worker and module
    module_stem = Path(request.node.fspath).stem
    temp_report_dir = Path("coverage") / worker_id / f"{module_stem}_temp_reports"
    temp_report_dir.mkdir(parents=True, exist_ok=True)
    report_files_generated = []  # Keep track of files to aggregate

    def _collect_coverage(
        cairo_file: Path,
        trace: pl.DataFrame,
    ) -> None:
        """
        Calculates coverage for a single test run and writes it to a temporary file.  We write the
        local coverage report to a parquet file, as keeping it in memory would consume too much
        memory when running the entire test suite.
        This parquet file can the be loaded on demand.
        Args:
            cairo_file: Path to the Cairo source file relevant to this run.
            trace: Polars DataFrame containing the execution trace (pc, ap, fp).
        """
        try:
            coverage_df = coverage_from_trace(cairo_file, trace)

            # Generate a unique filename for this report
            # Sanitize node name to create a valid filename component
            sanitized_node_name = (
                request.node.name.replace("[", "_")
                .replace("]", "")
                .replace("/", "_")
                .replace(":", "_")
                .replace(" ", "_")
            )
            report_filename = f"{sanitized_node_name}_{uuid.uuid4()}.parquet"
            report_filepath = temp_report_dir / report_filename

            # Write the report to the temporary file
            coverage_df.write_parquet(report_filepath)
            report_files_generated.append(report_filepath)

        except Exception as e:
            logger.exception(
                f"Error during coverage calculation or writing for node {str(request.node)}: {e}"
            )
            return

        return

    # Yield the collector function to be used by the test runner
    yield _collect_coverage

    # --- Start of Fixture Teardown (runs after all tests in the module) ---
    try:
        if not report_files_generated:
            logger.info(
                f"[Coverage] Module {module_stem}: No reports generated, skipping aggregation."
            )
        else:
            _aggregate_coverage(
                cairo_files,
                module_stem,
                report_files_generated,
                temp_report_dir,
                worker_id,
            )
    except Exception as e:
        logger.exception(
            f"Error during coverage aggregation for module {module_stem}: {e}"
        )
    finally:
        # --- Cleanup Phase ---
        # Always attempt to clean up the temporary directory
        if temp_report_dir.exists():
            shutil.rmtree(temp_report_dir)

    return


def _aggregate_coverage(
    cairo_files: List[Path],
    module_stem: str,
    report_files_generated: List[Path],
    temp_report_dir: Path,
    worker_id: str,
):
    logger.info(
        f"[Coverage] Worker {worker_id}, Module {module_stem}: Aggregating {len(report_files_generated)} reports from {temp_report_dir}."
    )
    # Scan all generated parquet files lazily
    scanned_reports = [
        pl.scan_parquet(report_file) for report_file in report_files_generated
    ]

    if not scanned_reports:
        logger.info(
            f"[Coverage] Worker {worker_id}, Module {module_stem}: Found no reports to scan in {temp_report_dir}."
        )
        return

    # Concatenate the lazy scans
    concatenated_lazy = pl.concat(scanned_reports)

    # Aggregate coverage per relevant Cairo file for this module
    for cairo_file in cairo_files:
        # Load base statement info (all executable lines)
        dump_path = get_dump_path(cairo_file)
        df_pickle_path_str = str(dump_path).replace(".pickle", "_dataframes.pickle")
        df_pickle_path = Path(df_pickle_path_str)
        if df_pickle_path.exists():
            with df_pickle_path.open("rb") as f:
                dataframes = pickle.load(f)
                all_statements = dataframes["all_statements"]
        else:
            raise Exception(
                f"[Coverage] Worker {worker_id}: Dataframes pickle not found: {df_pickle_path}"
            )

        # Combine base statements with concatenated coverage data lazily
        all_coverages_lazy = (
            pl.concat(
                [all_statements.lazy(), concatenated_lazy]
            )  # Ensure both are lazy
            .filter(~pl.col("filename").str.contains(".venv"))  # Exclude venv
            .filter(~pl.col("filename").str.contains("test_"))  # Exclude test files
            .group_by(pl.col("filename"), pl.col("line_number"))
            .agg(pl.col("count").sum())  # Sum counts for each line
        )

        # Collect the final aggregated data (potential memory peak)
        all_coverages_df = all_coverages_lazy.collect()

        # --- Reporting and JSON Dump ---
        with pl.Config(tbl_rows=100, fmt_str_lengths=120):
            # Calculate missed lines for the specific cairo_file
            missed = (
                all_coverages_df.lazy()
                .filter(pl.col("filename") == str(cairo_file))
                .filter(pl.col("count") == 0)  # Lines with 0 hits
                .select(  # Select filename and line number for missed report
                    (
                        pl.col("filename").str.replace(str(Path.cwd()) + "/", "")
                        + ":"
                        + pl.col("line_number").cast(pl.String)
                    ).alias("missed_line")
                )
                .sort("missed_line")  # Sort alphabetically
            ).collect()

            # Log coverage results
            if missed.height > 0:
                # Use print for cleaner output of missed lines report in CI logs
                print(f"Missed lines in {cairo_file}:\n{missed}")
            else:
                logger.info(f"{cairo_file}: 100% coverage ✅")

        # Prepare data structure for JSON dump
        # Aggregate line numbers and counts per filename for the final JSON
        all_coverages_dict = (
            all_coverages_df.lazy()  # Start lazy again for efficient grouping
            .group_by("filename")
            .agg(pl.col("line_number"), pl.col("count"))
            .collect()
            .to_dict(as_series=False)
        )

        coverage_data = {
            "coverage": {
                filename: dict(
                    zip(line_number, count)
                )  # Combine lines and counts into {line: count} dict
                for filename, line_number, count in zip(
                    all_coverages_dict["filename"],
                    all_coverages_dict["line_number"],
                    all_coverages_dict["count"],
                )
            }
        }

        # Define final output path and dump JSON
        final_dump_path = (
            Path("coverage")
            / worker_id
            / cairo_file.relative_to(Path.cwd()).with_suffix(".json")
        )
        final_dump_path.parent.mkdir(parents=True, exist_ok=True)
        logger.info(f"Dumping final coverage JSON to {final_dump_path}")
        with open(final_dump_path, "w") as f:
            json.dump(coverage_data, f, indent=4)
    return


@pytest.fixture(scope="module")
def cairo_run_py(
    request,
    cairo_programs,
    cairo_files,
    main_paths,
    coverage,
):
    """Run the cairo program using Python VM."""
    return run_python_vm(
        cairo_programs,
        cairo_files,
        main_paths,
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
            request,
            coverage=coverage,
            hint_locals={"get_op": get_op},
        )

    return run_rust_vm(
        cairo_programs,
        rust_programs,
        cairo_files,
        main_paths,
        request,
        coverage=coverage,
    )

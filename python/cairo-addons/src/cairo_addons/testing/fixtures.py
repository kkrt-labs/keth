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
from typing import List, Tuple

import polars as pl
import pytest
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME
from starkware.cairo.lang.compiler.program import Program

from cairo_addons.testing.coverage import coverage_from_trace
from cairo_addons.testing.runner import run_python_vm, run_rust_vm
from cairo_addons.vm import Program as RustProgram

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
def cairo_program(request) -> List[Program]:
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
def coverage(cairo_programs: List[Program], cairo_files: List[Path], worker_id: str):
    """
    Fixture to collect coverage from all tests, then merge and dump it as a json file for codecov.
    """
    reports = []
    yield coverage_from_trace(cairo_programs, cairo_files, reports)

    # If no coverage is collected, don't dump anything
    # This can happen if the all the tests raise Cairo exceptions
    if not reports:
        return

    for cairo_program, cairo_file in zip(cairo_programs, cairo_files):
        all_statements = pl.DataFrame(
            [
                {
                    "filename": instruction.inst.input_file.filename,
                    "line_number": i,
                }
                for instruction in cairo_program.debug_info.instruction_locations.values()
                # No scope other than the global scope means that it's a dw instruction
                if len(instruction.accessible_scopes) > 1
                for i in range(
                    instruction.inst.start_line, instruction.inst.end_line + 1
                )
            ]
        ).with_columns(
            filename=(
                pl.when(pl.col("filename") == "")
                .then(pl.lit(str(cairo_file)))
                .otherwise(pl.col("filename"))
            ),
            count=pl.lit(0, dtype=pl.UInt32),
        )
        all_coverages = (
            pl.concat([all_statements, pl.concat(reports)])
            .filter(~pl.col("filename").str.contains(".venv"))
            .filter(~pl.col("filename").str.contains("test_"))
            .group_by(pl.col("filename"), pl.col("line_number"))
            .agg(pl.col("count").sum())
        )
        with pl.Config() as cfg:
            cfg.set_tbl_rows(100)
            cfg.set_fmt_str_lengths(90)
            missed = (
                all_coverages.filter(pl.col("filename") == str(cairo_file))
                .with_columns(
                    pl.col("filename").str.replace(str(Path().cwd()) + "/", "")
                )
                .filter(pl.col("count") == 0)
                .sort("line_number", descending=False)
                .with_columns(
                    pl.col("filename") + ":" + pl.col("line_number").cast(pl.String)
                )
                .drop("line_number", "count")
            )
            if missed.height > 0:
                print(missed)
            else:
                logger.info(f"{str(cairo_file)}: 100% coverage ✅")
        all_coverages = (
            all_coverages.group_by("filename")
            .agg(pl.col("line_number"), pl.col("count"))
            .to_dict(as_series=False)
        )
        dump_path = (
            Path("coverage")
            / worker_id
            / cairo_file.relative_to(Path().cwd()).with_suffix(".json")
        )
        dump_path.parent.mkdir(parents=True, exist_ok=True)
        json.dump(
            {
                "coverage": {
                    filename: dict(zip(line_number, count))
                    for filename, line_number, count in zip(
                        all_coverages["filename"],
                        all_coverages["line_number"],
                        all_coverages["count"],
                    )
                }
            },
            open(dump_path, "w"),
        )

    return reports


@pytest.fixture(scope="module")
def cairo_run_py(
    cairo_programs,
    cairo_files,
    main_paths,
    request,
    coverage,
):
    """Run the cairo program using Python VM."""
    return run_python_vm(
        cairo_programs,
        cairo_files,
        main_paths,
        request,
        coverage,
    )


@pytest.fixture(scope="module")
def cairo_run(
    cairo_programs,
    rust_programs,
    cairo_files,
    main_paths,
    request,
    python_vm: bool,
    coverage,
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
        )

    return run_rust_vm(
        cairo_programs,
        rust_programs,
        cairo_files,
        main_paths,
        request,
        coverage=coverage,
    )

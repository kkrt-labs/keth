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
def cairo_file(request):
    return request.session.cairo_files[request.node.fspath]


@pytest.fixture(scope="module")
def cairo_program(request) -> Program:
    return request.session.cairo_programs[request.node.fspath]


@pytest.fixture(scope="module")
def main_path(request):
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
def rust_program(cairo_program: Program, python_vm: bool) -> RustProgram:
    if python_vm:
        return None

    return RustProgram.from_bytes(
        json.dumps(cairo_program.Schema().dump(cairo_program)).encode()
    )


@pytest.fixture(scope="module")
def coverage(cairo_program: Program, cairo_file: Path, worker_id: str):
    """
    Fixture to collect coverage from all tests, then merge and dump it as a json file for codecov.
    """
    reports = []

    yield coverage_from_trace(cairo_program, cairo_file, reports)

    # If no coverage is collected, don't dump anything
    # This can happen if the all the tests raise Cairo exceptions
    if not reports:
        return

    all_coverages = (
        pl.concat(reports)
        .group_by(pl.col("filename"), pl.col("line_number"))
        .agg(pl.col("count").sum())
        .group_by("filename")
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
def cairo_run_py(cairo_program, cairo_file, main_path, request, coverage):
    """Run the cairo program using Python VM."""
    return run_python_vm(cairo_program, cairo_file, main_path, request, coverage)


@pytest.fixture(scope="module")
def cairo_run(
    cairo_program,
    rust_program,
    cairo_file,
    main_path,
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
            cairo_program, cairo_file, main_path, request, coverage=coverage
        )

    return run_rust_vm(
        cairo_program, rust_program, cairo_file, main_path, request, coverage=coverage
    )

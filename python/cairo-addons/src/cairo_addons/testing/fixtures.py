"""
Cairo Test System - Runtime and Type Integration

This module handles the execution of Cairo programs and provides the core integration
with the type system for testing. It enables running tests with inputs passed as pure Python by automatically
handling type conversion between Python and Cairo.

The runner works with args_gen.py and serde.py for automatic type conversion.
"""

import json
import logging

import pytest
from starkware.cairo.lang.compiler.program import Program

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
def rust_program(request, cairo_program: Program) -> RustProgram:
    if request.node.get_closest_marker("python_vm"):
        return None

    return RustProgram.from_bytes(
        json.dumps(cairo_program.Schema().dump(cairo_program)).encode()
    )


@pytest.fixture(scope="module")
def cairo_run_py(cairo_program, cairo_file, main_path, request):
    """Run the cairo program using Python VM."""
    return run_python_vm(cairo_program, cairo_file, main_path, request)


@pytest.fixture(scope="module")
def cairo_run(cairo_program, rust_program, cairo_file, main_path, request):
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
    if request.node.get_closest_marker("python_vm"):
        return run_python_vm(cairo_program, cairo_file, main_path, request)

    return run_rust_vm(cairo_program, rust_program, cairo_file, main_path, request)

import logging
from pathlib import Path
from time import perf_counter

import pytest
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME
from starkware.cairo.lang.compiler.cairo_compile import compile_cairo, get_module_reader
from starkware.cairo.lang.compiler.preprocessor.default_pass_manager import (
    default_pass_manager,
)

from tests.utils.hints import implement_hints

logger = logging.getLogger()


def cairo_compile(path):
    module_reader = get_module_reader(cairo_path=[str(Path(__file__).parents[2])])

    pass_manager = default_pass_manager(
        prime=DEFAULT_PRIME, read_module=module_reader.read
    )

    return compile_cairo(
        Path(path).read_text(),
        pass_manager=pass_manager,
        debug_info=True,
    )


@pytest.fixture(scope="module")
def cairo_file(request):
    cairo_file = Path(request.node.fspath).with_suffix(".cairo")
    if not cairo_file.exists():
        # No dedicated cairo file for tests in the tests/ directory
        # Use the main cairo file directly
        cairo_file = Path(str(cairo_file).replace("/tests", "").replace("/test_", "/"))
        if not cairo_file.exists():
            raise ValueError(f"Missing cairo file: {cairo_file}")
    return cairo_file


@pytest.fixture(scope="module")
def cairo_program(cairo_file):
    start = perf_counter()
    program = cairo_compile(cairo_file)
    program.hints = implement_hints(program)
    stop = perf_counter()
    logger.info(f"{cairo_file} compiled in {stop - start:.2f}s")
    return program


@pytest.fixture(scope="module")
def main_path(cairo_file):
    """
    Resolve the __main__ part of the cairo scope path.
    """
    parts = cairo_file.relative_to(Path.cwd()).with_suffix("").parts
    return parts[1:] if parts[0] == "cairo" else parts

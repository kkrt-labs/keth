import logging
from pathlib import Path
from time import perf_counter

import pytest
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME
from starkware.cairo.lang.compiler.cairo_compile import compile_cairo, get_module_reader
from starkware.cairo.lang.compiler.preprocessor.default_pass_manager import (
    default_pass_manager,
)
from starkware.cairo.lang.compiler.scoped_name import ScopedName

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
def main_path(cairo_file):
    """
    Resolve the __main__ part of the cairo scope path.
    """
    parts = cairo_file.relative_to(Path.cwd()).with_suffix("").parts
    return parts[1:] if parts[0] == "cairo" else parts


@pytest.fixture(scope="module")
def cairo_program(cairo_file, main_path):
    start = perf_counter()
    program = cairo_compile(cairo_file)
    program.hints = implement_hints(program)
    all_identifiers = list(program.identifiers.dict.items())
    # when running the tests, the main file is the test file
    # and the compiler is not able to find struct defined therein
    # in a breakpoint, looking for, e.g. ethereum.cancun.trie.InternalNode
    # while only __main__.InternalNode exists.
    # There is probably a better way to solve this at the IdentifierManager.
    for k, v in all_identifiers:
        if "__main__" not in str(k):
            continue
        program.identifiers.add_identifier(ScopedName(main_path + k.path[1:]), v)
    stop = perf_counter()
    logger.info(f"{cairo_file} compiled in {stop - start:.2f}s")
    return program

import logging
from pathlib import Path
from time import perf_counter

from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME
from starkware.cairo.lang.compiler.scoped_name import ScopedName

from src.utils.compiler import cairo_compile, implement_hints

logger = logging.getLogger()


def get_cairo_file(location):
    cairo_file = Path(location).with_suffix(".cairo")
    if not cairo_file.exists():
        cairo_file = Path(str(cairo_file).replace("/tests", "").replace("/test_", "/"))
    if not cairo_file.exists():
        raise ValueError(f"Missing cairo file: {cairo_file}")
    return cairo_file


def get_main_path(cairo_file):
    """
    Resolve the __main__ part of the cairo scope path.
    """
    return tuple(
        "/".join(cairo_file.relative_to(Path.cwd()).with_suffix("").parts)
        .replace("cairo/", "")
        .split("/")
    )


def get_cairo_program(cairo_file, main_path):
    start = perf_counter()
    program = cairo_compile(cairo_file, debug_info=True, proof_mode=False)
    program.hints = implement_hints(program)
    all_identifiers = list(program.identifiers.dict.items())
    # when running the tests, the main file is the test file
    # and the compiler is not able to find struct defined therein
    # in a breakpoint, looking for, e.g. ethereum.cancun.trie.InternalNode
    # while only __main__.InternalNode exists.
    # There is probably a better way to solve this at the IdentifierManager level.
    for k, v in all_identifiers:
        if "__main__" not in str(k):
            continue
        program.identifiers.add_identifier(ScopedName(main_path + k.path[1:]), v)
    stop = perf_counter()
    logger.info(f"{cairo_file} compiled in {stop - start:.2f}s")
    return program

"""
Cairo Test System - Compilation and File Resolution

This module handles the compilation of Cairo files and test file resolution.
It provides the infrastructure needed to locate and compile Cairo files for testing.

Automatic Test File Resolution is implemented as follows:
   - When running a Python test file test_xxx.py:
     a) First looks for test_xxx.cairo in the same directory
     b) If not found, looks for xxx.cairo in the main codebase
     c) Follows project directory structure for test organization
"""

import json
import logging
from pathlib import Path
from time import perf_counter
from typing import Optional

from starkware.cairo.lang.compiler.program import Program
from starkware.cairo.lang.compiler.scoped_name import ScopedName

from src.utils.compiler import cairo_compile, implement_hints

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger()


def get_cairo_file(location):
    """
    Locate the Cairo file corresponding to a Python test file.

    Resolution Strategy:
    1. Look for test_xxx.cairo in tests/
    2. If not found, look for xxx.cairo in main codebase
    3. Raise error if neither exists

    This allows writing Python tests without creating Cairo test files,
    leveraging the automatic type conversion system.
    """
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


def get_cairo_program(cairo_file: Path, main_path, dump_path: Optional[Path] = None):
    start = perf_counter()
    if dump_path is not None and dump_path.is_file():
        logger.info(f"Loading program from {dump_path}")
        program = Program.load(data=json.loads(dump_path.read_text()))
    else:
        logger.info(f"Compiling {cairo_file}")
        program = cairo_compile(cairo_file, debug_info=True, proof_mode=False)
        if dump_path is not None:
            dump_path.with_suffix(".lock").write_text(
                json.dumps(program.Schema().dump(program), indent=4, sort_keys=True)
            )
            dump_path.with_suffix(".lock").rename(dump_path)

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
    logger.info(f"{cairo_file} loaded in {stop - start:.2f}s")

    return program

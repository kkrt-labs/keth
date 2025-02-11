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

import logging
import pickle
from pathlib import Path
from time import perf_counter
from typing import List, Optional, Tuple, Union

from starkware.cairo.lang.compiler.cairo_compile import DEFAULT_PRIME
from starkware.cairo.lang.compiler.scoped_name import ScopedName

from cairo_addons.compiler import cairo_compile, implement_hints

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger()


def get_cairo_files(location: Union[str, Path]) -> List[Path]:
    """
    Locate the Cairo file corresponding to a Python test file.

    Resolution Strategy:
    1. Look for xxx.cairo in main codebase
    2. Look for test_xxx.cairo in main codebase
    3. Raise if none found
    4. Return files found, starting with the source file

    This allows writing Python tests without creating Cairo test files,
    leveraging the automatic type conversion system.
    """
    output = []
    test_cairo_file = Path(location).with_suffix(".cairo")
    main_cairo_file = Path(
        str(test_cairo_file).replace("/tests", "").replace("/test_", "/")
    )
    if main_cairo_file.exists():
        output.append(main_cairo_file)
    if test_cairo_file.exists():
        output.append(test_cairo_file)
    if not output:
        raise ValueError(f"Missing cairo file: {main_cairo_file}")
    return output


def get_main_path(cairo_file: Optional[str]) -> Optional[Tuple[str]]:
    """
    Resolve the __main__ part of the cairo scope path.
    """
    if not cairo_file:
        return None
    return tuple(
        "/".join(cairo_file.relative_to(Path.cwd()).with_suffix("").parts)
        .replace("cairo/", "")
        .split("/")
    )


def get_cairo_program(
    cairo_file: Path,
    main_path,
    dump_path: Optional[Path] = None,
    prime: int = DEFAULT_PRIME,
):
    start = perf_counter()
    if dump_path is not None and dump_path.is_file():
        logger.info(f"Loading program from {dump_path}")
        with dump_path.open("rb") as f:
            program = pickle.load(f)
    else:
        logger.info(f"Compiling {cairo_file}")
        program = cairo_compile(
            str(cairo_file), debug_info=True, proof_mode=False, prime=prime
        )
        if dump_path is not None:
            dump_path.parent.mkdir(parents=True, exist_ok=True)
            with dump_path.with_suffix(".lock").open("wb") as f:
                pickle.dump(program, f)
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

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
from typing import List, Optional, Tuple

import pytest
from starkware.cairo.lang.compiler.cairo_compile import DEFAULT_PRIME
from starkware.cairo.lang.compiler.scoped_name import ScopedName

from cairo_addons.compiler import cairo_compile, implement_hints

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger()


def resolve_cairo_file(
    fspath: Path,
    item: pytest.Item,
) -> List[Path]:
    """
    Resolve Cairo source files by checking for a cairo_file marker,
    then falling back to the default resolution.

    Default Resolution Strategy:
    1. Look for xxx.cairo in main codebase
    2. Look for test_xxx.cairo in main codebase
    3. Raise if none found
    4. Return files found, starting with the source file

    This allows writing Python tests without creating Cairo test files,
    leveraging the automatic type conversion system.

    Args:
        fspath: The path to the test file
        item: The test item being processed

    Returns:
        List of resolved Cairo file paths
    """
    files = []

    # Check for cairo_file marker
    marker = item.get_closest_marker("cairo_file")
    if marker:
        try:
            path = Path(marker.args[0])
            if not isinstance(path, Path):
                path = Path(path)

            if not path.is_absolute():
                path = Path.cwd() / path

            if not path.exists():
                raise FileNotFoundError(
                    f"cairo_file marker points to non-existent path: {path}"
                )

            files.append(path)

        except Exception as exc:
            logger.warning(
                f"Failed to resolve Cairo path using marker for {fspath} ({exc}), "
                "falling back to standard resolution."
            )

    # Fall back to standard resolution if marker not found or invalid
    if not files:
        try:
            test_cairo_file = Path(fspath).with_suffix(".cairo")
            main_cairo_file = Path(
                str(test_cairo_file).replace("/tests", "").replace("/test_", "/")
            )
            if main_cairo_file.exists():
                files.append(main_cairo_file)
            if test_cairo_file.exists():
                files.append(test_cairo_file)
            if not files:
                raise ValueError(f"Missing cairo file: {main_cairo_file}")
            return files
        except ValueError as exc:
            raise ValueError(
                f"Could not resolve Cairo files for {fspath}. "
                f"Marker resolution failed and standard resolution failed: {exc}"
            ) from exc

    return files


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

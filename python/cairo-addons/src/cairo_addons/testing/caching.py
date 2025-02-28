import os
import time
from pathlib import Path

import xxhash
from starkware.cairo.lang.compiler.program import Program

CACHED_TESTS_FILE = "cached_tests.json"
CAIRO_DIR_TIMESTAMP_FILE = "cairo_dir_timestamp.json"


def file_hash(file_path: str | Path) -> bytes:
    """
    A simple, fast, hash of any kind of file.
    """
    file_path = Path(file_path)
    with open(file_path, "rb") as f:
        file_hash = xxhash.xxh64(f.read()).digest()
    return file_hash


def program_hash(program: Program) -> bytes:
    """
    A simple, fast, hash of the program.

    The hashing is made after hints are implemented so that changing hints implementation
    will invalidate the cache.
    """
    if program.compiler_version is None:
        raise ValueError("Program compiler version is not set")

    bytes_data = (
        program.compiler_version.encode()
        + program.prime.to_bytes(32, "little")
        + b"".join(x.to_bytes(32, "little") for x in program.data)
        + b"".join([b.encode() for b in program.builtins])
        + b"".join(
            [
                k.to_bytes(32, "little") + b"".join([hint.code.encode() for hint in v])
                for k, v in program.hints.items()
            ]
        )
    )
    return xxhash.xxh64(bytes_data).digest()


def has_cairo_dir_changed(
    cairo_dir: Path = Path("cairo"), timestamp: float = 0
) -> bool:
    """
    Check if any file in the cairo directory has been modified since the given timestamp.

    Args:
        cairo_dir: Path to the cairo directory
        timestamp: Timestamp to compare against

    Returns:
        True if any file has been modified since the timestamp, False otherwise
    """
    if not cairo_dir.exists():
        return False

    for root, _, files in os.walk(cairo_dir):
        for file in files:
            if not file.endswith(".cairo"):
                continue

            file_path = Path(root) / file
            if os.path.getmtime(file_path) > timestamp:
                return True

    return False

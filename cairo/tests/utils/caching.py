from pathlib import Path

import xxhash

CACHED_TESTS_FILE = "cached_tests.json"


def file_hash(file_path: str | Path) -> bytes:
    """
    A simple, fast, hash of any kind of file.
    """
    file_path = Path(file_path)
    with open(file_path, "rb") as f:
        file_hash = xxhash.xxh64(f.read()).digest()
    return file_hash


def program_hash(program) -> bytes:
    """
    A simple, fast, hash of the program.

    The hashing is made after hints are implemented so that changing hints implementation
    will invalidate the cache.
    """
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

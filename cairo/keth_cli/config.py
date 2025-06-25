"""Centralized configuration for Keth CLI."""

from pathlib import Path
from typing import Dict


class KethConfig:
    """Centralized configuration for Keth CLI."""

    # Fork constants
    PRAGUE_FORK_BLOCK = 22615247

    # Chain constants
    DEFAULT_CHAIN_ID = 1

    # ZKPI constants
    DEFAULT_ZKPI_VERSION = "1"

    # Default body chunk size for AR input generation
    DEFAULT_BODY_CHUNK_SIZE = 10

    # Default data directory
    DEFAULT_DATA_DIR = Path("data")

    # Compiled program paths
    COMPILED_PROGRAMS: Dict[str, Path] = {
        "main": Path("build/main_compiled.json"),
        "init": Path("build/init_compiled.json"),
        "body": Path("build/body_compiled.json"),
        "teardown": Path("build/teardown_compiled.json"),
        "aggregator": Path("build/aggregator_compiled.json"),
        "mpt_diff": Path("build/mpt_diff_compiled.json"),
    }

    # Program hashes file
    PROGRAM_HASHES_FILE = Path("build/program_hashes.json")

    # File naming patterns
    PROVER_INPUT_PREFIX = "prover_input_info"
    CAIRO_PIE_PREFIX = "cairo_pie"
    PROOF_PREFIX = "proof"

    # Output file extensions
    RUN_OUTPUT_EXT = ".run_output.txt"
    CAIRO_PIE_EXT = ".zip"
    PROOF_EXT = ".json"

    # MPT diff configuration
    MPT_DIFF_BRANCHES = 16

    # Logging configuration
    LOG_LEVEL = "INFO"
    LOG_FORMAT = "%(message)s"
    LOG_DATE_FORMAT = "[%X]"

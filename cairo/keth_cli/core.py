"""Core utilities for Keth CLI including context management and path utilities."""

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from .config import KethConfig
from .exceptions import (
    InvalidBlockNumberError,
    InvalidChainIdError,
    ZkpiFileNotFoundError,
)


@dataclass
class KethContext:
    """Shared context for Keth operations."""

    data_dir: Path
    chain_id: int
    block_number: int
    zkpi_version: str
    proving_run_id: str
    zkpi_path: Path
    proving_run_dir: Path
    config: KethConfig

    @classmethod
    def create(
        cls,
        config: KethConfig,
        data_dir: Path,
        block_number: int,
        chain_id: Optional[int] = None,
        zkpi_version: Optional[str] = None,
        proving_run_id: Optional[str] = None,
    ) -> "KethContext":
        """Create a KethContext with automatic resolution of missing values."""
        # Use default values from config if not provided
        if zkpi_version is None:
            zkpi_version = config.DEFAULT_ZKPI_VERSION

        # Resolve chain ID if not provided
        if chain_id is None:
            chain_id = _resolve_chain_id(config, data_dir, block_number, zkpi_version)

        # Validate ZKPI file exists
        zkpi_path = get_zkpi_path(data_dir, chain_id, block_number, zkpi_version)
        if not zkpi_path.exists():
            raise ZkpiFileNotFoundError(str(zkpi_path), chain_id, block_number)

        # Resolve proving run ID if not provided
        if proving_run_id is None:
            proving_run_id = get_next_proving_run_id(data_dir, chain_id, block_number)

        # Create proving run directory
        proving_run_dir = get_proving_run_dir(
            data_dir, chain_id, block_number, proving_run_id
        )
        proving_run_dir.mkdir(parents=True, exist_ok=True)

        return cls(
            data_dir=data_dir,
            chain_id=chain_id,
            block_number=block_number,
            zkpi_version=zkpi_version,
            proving_run_id=proving_run_id,
            zkpi_path=zkpi_path,
            proving_run_dir=proving_run_dir,
            config=config,
        )


def _resolve_chain_id(
    config: KethConfig, data_dir: Path, block_number: int, zkpi_version: str
) -> int:
    """Resolve chain ID from ZKPI file."""
    zkpi_path = get_zkpi_path(
        data_dir, config.DEFAULT_CHAIN_ID, block_number, zkpi_version
    )
    if not zkpi_path.exists():
        raise ZkpiFileNotFoundError(
            str(zkpi_path), config.DEFAULT_CHAIN_ID, block_number
        )
    return get_chain_id_from_zkpi(zkpi_path)


def get_next_proving_run_id(data_dir: Path, chain_id: int, block_number: int) -> str:
    """Get the next sequential proving run ID for a given chain and block."""
    block_dir = data_dir / str(chain_id) / str(block_number)
    if not block_dir.exists():
        return "1"

    # Find existing proving run directories
    existing_runs = []
    for item in block_dir.iterdir():
        if item.is_dir() and item.name.isdigit():
            existing_runs.append(int(item.name))

    return str(max(existing_runs, default=0) + 1)


def get_zkpi_path(
    data_dir: Path, chain_id: int, block_number: int, version: str = "1"
) -> Path:
    """Get the path to the ZKPI file for a given chain, block, and version."""
    return data_dir / str(chain_id) / str(block_number) / "zkpi.json"


def get_proving_run_dir(
    data_dir: Path, chain_id: int, block_number: int, proving_run_id: str
) -> Path:
    """Get the proving run directory for a given chain, block, and proving run ID."""
    return data_dir / str(chain_id) / str(block_number) / proving_run_id


def get_chain_id_from_zkpi(zkpi_path: Path) -> int:
    """Extract chain ID from ZKPI file."""
    try:
        with open(zkpi_path, "r") as f:
            zkpi_data = json.load(f)
        return zkpi_data["chainConfig"]["chainId"]
    except (FileNotFoundError, KeyError, json.JSONDecodeError) as e:
        raise InvalidChainIdError(f"Error reading chain ID from {zkpi_path}: {e}")


def validate_block_number(block_number: int, config: KethConfig) -> None:
    """Validate that the block number is after prague fork."""
    if block_number < config.PRAGUE_FORK_BLOCK:
        raise InvalidBlockNumberError(block_number, config.PRAGUE_FORK_BLOCK)

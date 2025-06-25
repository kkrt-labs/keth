"""Custom exceptions for Keth CLI."""


class KethError(Exception):
    """Base exception for all Keth CLI errors."""

    pass


class ZkpiFileNotFoundError(KethError):
    """Raised when a ZKPI file cannot be found."""

    def __init__(self, zkpi_path: str, chain_id: int, block_number: int):
        self.zkpi_path = zkpi_path
        self.chain_id = chain_id
        self.block_number = block_number
        super().__init__(
            f"ZKPI file not found at {zkpi_path} for chain {chain_id}, block {block_number}"
        )


class InvalidStepParametersError(KethError):
    """Raised when step parameters are invalid."""

    def __init__(self, step: str, message: str):
        self.step = step
        super().__init__(f"Invalid parameters for {step} step: {message}")


class ProgramHashNotFoundError(KethError):
    """Raised when a program hash cannot be found."""

    def __init__(self, program_name: str):
        self.program_name = program_name
        super().__init__(f"Program hash not found for {program_name}")


class InvalidBlockNumberError(KethError):
    """Raised when block number is invalid (e.g., before Prague fork)."""

    def __init__(self, block_number: int, fork_block: int):
        self.block_number = block_number
        self.fork_block = fork_block
        super().__init__(f"Block {block_number} is before Prague fork ({fork_block})")


class MissingSegmentOutputError(KethError):
    """Raised when required segment outputs are missing for aggregator."""

    def __init__(self, step: str, proving_run_dir: str):
        self.step = step
        self.proving_run_dir = proving_run_dir
        super().__init__(f"No {step} output files found in {proving_run_dir}")


class InvalidChainIdError(KethError):
    """Raised when chain ID cannot be determined or is invalid."""

    def __init__(self, message: str):
        super().__init__(f"Invalid chain ID: {message}")


class CompiledProgramNotFoundError(KethError):
    """Raised when a compiled program file is not found."""

    def __init__(self, program_path: str):
        self.program_path = program_path
        super().__init__(f"Compiled program not found at {program_path}")


class InvalidBranchIndexError(KethError):
    """Raised when MPT diff branch index is out of valid range."""

    def __init__(self, branch_index: int):
        self.branch_index = branch_index
        super().__init__(f"Branch index {branch_index} is out of range (must be 0-15)")

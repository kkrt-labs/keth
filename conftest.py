import logging
import os

import pytest
from dotenv import load_dotenv
from ethereum.trace import (
    EvmStop,
    GasAndRefund,
    OpEnd,
    OpException,
    OpStart,
    PrecompileEnd,
    PrecompileStart,
    TraceEvent,
    TransactionEnd,
    TransactionStart,
)
from hypothesis import HealthCheck, Phase, Verbosity, settings

from tests.utils.args_gen import Evm

load_dotenv()
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger()


def evm_trace(
    evm: Evm,
    event: TraceEvent,
    trace_memory: bool = False,
    trace_stack: bool = True,
    trace_return_data: bool = False,
) -> None:
    """
    Log the event.
    """
    import logging

    logger = logging.getLogger("TRACE")

    if isinstance(event, TransactionStart):
        pass
    elif isinstance(event, TransactionEnd):
        error_name = "None" if event.error is None else event.error.__class__.__name__
        logger.trace_eels(
            f"TransactionEnd: gas_used: {event.gas_used}, output: {event.output}, error: {error_name}"
        )
    elif isinstance(event, PrecompileStart):
        logger.trace_eels(f"PrecompileStart: {evm.message.code_address}")
    elif isinstance(event, PrecompileEnd):
        logger.trace_eels(f"PrecompileEnd: {evm.message.code_address}")
    elif isinstance(event, OpStart):
        op = event.op
        logger.trace_eels(f"OpStart: {hex(op.value)}")
    elif isinstance(event, OpEnd):
        logger.trace_eels("OpEnd")
    elif isinstance(event, OpException):
        logger.trace_eels(f"OpException: {event.error.__class__.__name__}")
    elif isinstance(event, EvmStop):
        logger.trace_eels("EvmStop")
    elif isinstance(event, GasAndRefund):
        logger.trace_eels(f"GasAndRefund: {event.gas_cost}")


def init_tracer():
    """Initialize the logger "trace" mode."""
    import logging

    from colorama import Fore, Style, init

    init()

    # Define TRACE level
    TRACE_LEVEL = logging.DEBUG - 5
    logging.addLevelName(TRACE_LEVEL, "TRACE")

    # Custom trace methods for Logger instances
    def trace(self, message, *args, **kwargs):
        if self.isEnabledFor(TRACE_LEVEL):
            colored_msg = f"{Fore.YELLOW}TRACE{Style.RESET_ALL} {message}"
            print(colored_msg)

    def trace_cairo(self, message, *args, **kwargs):
        if self.isEnabledFor(TRACE_LEVEL):
            colored_msg = f"{Fore.YELLOW}TRACE{Style.RESET_ALL} [CAIRO] {message}"
            print(colored_msg)

    def trace_eels(self, message, *args, **kwargs):
        if self.isEnabledFor(TRACE_LEVEL):
            colored_msg = f"{Fore.YELLOW}TRACE{Style.RESET_ALL} [EELS] {message}"
            print(colored_msg)

    def debug_cairo(self, message, *args, **kwargs):
        if self.isEnabledFor(logging.DEBUG):
            colored_msg = f"{Fore.BLUE}DEBUG{Style.RESET_ALL} [DEBUG-CAIRO] {message}"
            print(colored_msg)

    # Patch the logging module with our new trace methods
    setattr(logging, "TRACE", TRACE_LEVEL)
    setattr(logging.getLoggerClass(), "trace", trace)
    setattr(logging.getLoggerClass(), "trace_cairo", trace_cairo)
    setattr(logging.getLoggerClass(), "trace_eels", trace_eels)
    setattr(logging.getLoggerClass(), "debug_cairo", debug_cairo)


collect_ignore_glob = ["cairo/tests/ef_tests/fixtures/*"]


def pytest_configure(config):
    """
    Global test configuration for patching core classes.

    How it works:
    1. pytest runs this hook during test collection, before any tests execute
    2. We directly replace the class definitions in the original modules
    3. All subsequent imports of these modules will see our patched versions

    This effectively "rewrites" the module contents at the source, so whether code does:
    from ethereum.cancun.vm import Evm
    or:
        import ethereum.cancun.vm
        evm = ethereum.cancun.vm.Evm
    They both get our mock version, because the module itself has been modified.
    """
    from typing import Sequence, Union

    import ethereum
    import ethereum_rlp
    from ethereum_types.numeric import FixedUnsigned, Uint

    import mpt
    from tests.utils.args_gen import (
        EMPTY_ACCOUNT,
        Account,
        Environment,
        Evm,
        Message,
        MessageCallOutput,
        Node,
    )

    # Initialize the tracer
    init_tracer()

    # Apply patches at module level before any tests run
    ethereum.cancun.vm.Evm = Evm
    ethereum.cancun.vm.Message = Message
    ethereum.cancun.vm.Environment = Environment
    ethereum.cancun.vm.interpreter.MessageCallOutput = MessageCallOutput
    ethereum.cancun.fork_types.Account = Account
    ethereum.cancun.fork_types.EMPTY_ACCOUNT = EMPTY_ACCOUNT

    # TODO: Find a better way to do this?
    # See explanation below. Lots of EELS modules import `Account` and `EMPTY_ACCOUNT` from `ethereum.cancun.fork_types`.
    # I think these modules get loaded before this patch is applied. Thus we must replace them manually.
    setattr(ethereum.cancun.trie, "Account", Account)
    setattr(ethereum.cancun.state, "Account", Account)
    setattr(ethereum.cancun.state, "EMPTY_ACCOUNT", EMPTY_ACCOUNT)
    setattr(ethereum.cancun.fork_types, "EMPTY_ACCOUNT", EMPTY_ACCOUNT)
    setattr(ethereum.cancun.vm.instructions.environment, "EMPTY_ACCOUNT", EMPTY_ACCOUNT)
    setattr(mpt.utils, "Account", Account)

    ethereum.cancun.trie.Node = Node
    setattr(ethereum.cancun.trie, "Node", Node)

    # Mock the Extended type
    ethereum_rlp.rlp.Extended = Union[Sequence["Extended"], bytearray, bytes, Uint, FixedUnsigned, str, bool]  # type: ignore # noqa: F821

    # Patching evm_trace:
    # - Problem: Global patches of `ethereum.trace.evm_trace` are not reflected in places where `evm_trace` is imported in EELS.
    # - Cause: `ethereum.cancun.vm.interpreter` (and other modules) imports `evm_trace` locally (e.g., `from ethereum.trace import evm_trace`)
    #   at module load time, caching the original `discard_evm_trace`. Patching `ethereum.trace.evm_trace` later didn’t
    #   update this local reference due to Python’s import caching.
    # - Solution: Explicitly patch both `ethereum.trace.evm_trace` globally and
    #   `ethereum.cancun.vm.interpreter.evm_trace` locally (and other places where `evm_trace` is imported).
    if config.getoption("log_cli_level") == "TRACE":
        import ethereum.cancun.vm.interpreter

        setattr(ethereum.cancun.vm.interpreter, "evm_trace", evm_trace)
        setattr(ethereum.cancun.vm.gas, "evm_trace", evm_trace)


@pytest.fixture(autouse=True, scope="session")
def seed(request):
    if request.config.getoption("seed") is not None:
        import random

        logger.info(f"Setting seed to {request.config.getoption('seed')}")

        random.seed(request.config.getoption("seed"))


settings.register_profile(
    "nightly",
    deadline=None,
    max_examples=2000,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
    report_multiple_bugs=True,
    print_blob=True,
    suppress_health_check=[HealthCheck.too_slow],
)
settings.register_profile(
    "ci",
    deadline=None,
    max_examples=300,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
    print_blob=True,
    derandomize=True,
)
settings.register_profile(
    "fast",
    deadline=None,
    max_examples=1,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
    print_blob=True,
    derandomize=True,
)
settings.register_profile(
    "dev",
    deadline=None,
    max_examples=100,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
    derandomize=True,
    print_blob=True,
    verbosity=Verbosity.quiet,
)
settings.register_profile(
    "debug",
    max_examples=100,
    verbosity=Verbosity.verbose,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
    derandomize=True,
    print_blob=True,
)
settings.load_profile(os.getenv("HYPOTHESIS_PROFILE", "default"))
logger.info(f"Using Hypothesis profile: {os.getenv('HYPOTHESIS_PROFILE', 'default')}")

from dataclasses import fields

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

from tests.utils.args_gen import EMPTY_ACCOUNT, Evm

load_dotenv()


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

    import tests
    from tests.utils.args_gen import (
        Account,
        Environment,
        Evm,
        Message,
        MessageCallOutput,
        Node,
    )

    # Apply patches at module level before any tests run
    ethereum.cancun.vm.Evm = Evm
    ethereum.cancun.vm.Message = Message
    ethereum.cancun.vm.Environment = Environment
    ethereum.cancun.vm.interpreter.MessageCallOutput = MessageCallOutput
    ethereum.cancun.fork_types.Account = Account
    ethereum.cancun.fork_types.EMPTY_ACCOUNT = EMPTY_ACCOUNT

    # TODO: Find a better way to do this?
    # See explanation below. This is required for the `encode_node` function in `ethereum.cancun.trie` to work.
    setattr(ethereum.cancun.trie, "Account", Account)
    setattr(ethereum.cancun.state, "Account", Account)
    setattr(ethereum.cancun.state, "EMPTY_ACCOUNT", EMPTY_ACCOUNT)
    setattr(ethereum.cancun.fork_types, "EMPTY_ACCOUNT", EMPTY_ACCOUNT)

    ethereum.cancun.trie.Node = Node
    setattr(tests.utils.args_gen, "Node", Node)
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


def pytest_assertrepr_compare(op, left, right):
    """
    Custom assertion comparison for EVM objects to provide detailed field-by-field comparison.
    """
    if not (
        hasattr(left, "__class__")
        and hasattr(right, "__class__")
        and left.__class__.__name__ == "Evm"
        and right.__class__.__name__ == "Evm"
        and op == "=="
    ):
        return None

    lines = []
    for field in fields(left):
        left_val = getattr(left, field.name)
        right_val = getattr(right, field.name)

        if field.name != "error":
            # Regular field comparison
            if left_val != right_val:
                lines.extend(
                    [
                        f"{field.name} field mismatch:",
                        f"  left:  {left_val}",
                        f"  right: {right_val}",
                    ]
                )
        else:
            if left_val is not None and str(left_val) != str(right_val):
                lines.extend(
                    [
                        "error field mismatch:",
                        f"  left:  {left_val}",
                        f"  right: {right_val}",
                    ]
                )
            elif not isinstance(left_val, type(right_val)):
                lines.extend(
                    [
                        "error field mismatch:",
                        f"  left:  {type(left_val)}",
                        f"  right: {type(right_val)}",
                    ]
                )

    return lines if len(lines) > 0 else None

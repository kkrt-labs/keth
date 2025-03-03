from dataclasses import fields

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

from cairo_addons.testing.runner import run_python_vm, run_rust_vm
from tests.utils.args_gen import Evm
from tests.utils.args_gen import gen_arg as gen_arg_builder
from tests.utils.args_gen import to_cairo_type, to_python_type
from tests.utils.hints import get_op
from tests.utils.serde import Serde

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
        logger.trace(
            f"[EELS] TransactionEnd: gas_used: {event.gas_used}, output: {event.output}, error: {error_name}"
        )
    elif isinstance(event, PrecompileStart):
        logger.trace(f"[EELS] PrecompileStart: {evm.message.code_address}")
    elif isinstance(event, PrecompileEnd):
        logger.trace(f"[EELS] PrecompileEnd: {evm.message.code_address}")
    elif isinstance(event, OpStart):
        op = event.op
        logger.trace(f"[EELS] OpStart: {hex(op.value)}")
    elif isinstance(event, OpEnd):
        logger.trace("[EELS] OpEnd")
    elif isinstance(event, OpException):
        logger.trace(f"[EELS] OpException: {event.error.__class__.__name__}")
    elif isinstance(event, EvmStop):
        logger.trace("[EELS] EvmStop")
    elif isinstance(event, GasAndRefund):
        logger.trace(f"[EELS] GasAndRefund: {event.gas_cost}")


@pytest.fixture(scope="module")
def cairo_run_py(
    request,
    cairo_programs,
    cairo_files,
    main_paths,
    coverage,
):
    """Run the cairo program using Python VM."""
    return run_python_vm(
        cairo_programs,
        cairo_files,
        main_paths,
        request,
        gen_arg_builder=gen_arg_builder,
        serde_cls=Serde,
        to_python_type=to_python_type,
        to_cairo_type=to_cairo_type,
        hint_locals={"get_op": get_op},
        coverage=coverage,
    )


def init_tracer():
    import logging

    from colorama import Fore, Style, init

    init()

    # Define TRACE level
    TRACE_LEVEL = logging.DEBUG - 5
    levelName = "TRACE"
    methodName = levelName.lower()
    logging.addLevelName(TRACE_LEVEL, levelName)

    # Custom trace method for Logger instances
    def trace(self, message, *args, **kwargs):
        if self.isEnabledFor(TRACE_LEVEL):
            colored_msg = f"{Fore.YELLOW}TRACE{Style.RESET_ALL} {message}"
            print(colored_msg)

    # Patch the logging module with our new trace method
    setattr(logging, levelName, TRACE_LEVEL)
    setattr(logging.getLoggerClass(), methodName, trace)


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

    from tests.utils.args_gen import Environment, Evm, Message, MessageCallOutput

    init_tracer()

    # Apply patches at module level before any tests run
    ethereum.cancun.vm.Evm = Evm
    ethereum.cancun.vm.Message = Message
    ethereum.cancun.vm.Environment = Environment
    ethereum.cancun.vm.interpreter.MessageCallOutput = MessageCallOutput

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


@pytest.fixture(scope="module")
def cairo_run(
    request,
    cairo_programs,
    rust_programs,
    cairo_files,
    main_paths,
    coverage,
    python_vm,
):
    """
    Run the cairo program corresponding to the python test file at a given entrypoint with given program inputs as kwargs.
    Returns the output of the cairo program put in the output memory segment.

    When --profile-cairo is passed, the cairo program is run with the tracer enabled and the resulting trace is dumped.

    Logic is mainly taken from starkware.cairo.lang.vm.cairo_run with minor updates, mainly builtins discovery from implicit args.

    Type conversion between Python and Cairo is handled by:
    - gen_arg: Converts Python arguments to Cairo memory layout when preparing runner inputs
    - serde: Converts Cairo memory data to Python types by reading into the segments, used to return python types.

    The VM used for the run depends on the presence of a "python_vm" marker in the test.

    Returns:
        The function's return value, converted back to Python types
    """
    if python_vm:
        return run_python_vm(
            cairo_programs,
            cairo_files,
            main_paths,
            request,
            gen_arg_builder=gen_arg_builder,
            serde_cls=Serde,
            to_python_type=to_python_type,
            to_cairo_type=to_cairo_type,
            hint_locals={"get_op": get_op},
            coverage=coverage,
        )

    return run_rust_vm(
        cairo_programs,
        rust_programs,
        cairo_files,
        main_paths,
        request,
        gen_arg_builder=gen_arg_builder,
        serde_cls=Serde,
        to_python_type=to_python_type,
        coverage=coverage,
    )


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

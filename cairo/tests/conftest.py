import logging
import os
from dataclasses import fields

import pytest
from cairo_addons.testing.runner import run_python_vm, run_rust_vm
from dotenv import load_dotenv
from hypothesis import HealthCheck, Phase, Verbosity, settings

from tests.utils.args_gen import gen_arg as gen_arg_builder
from tests.utils.args_gen import to_cairo_type, to_python_type
from tests.utils.hints import get_op
from tests.utils.serde import Serde
from tests.utils.strategies import register_type_strategies

load_dotenv()
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger()


@pytest.fixture(autouse=True, scope="session")
def seed(request):
    if request.config.getoption("seed") is not None:
        import random

        logger.info(f"Setting seed to {request.config.getoption('seed')}")

        random.seed(request.config.getoption("seed"))


register_type_strategies()
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


@pytest.fixture(scope="module")
def cairo_run_py(request, cairo_program, cairo_file, main_path):
    """Run the cairo program using Python VM."""
    return run_python_vm(
        cairo_program,
        cairo_file,
        main_path,
        request,
        gen_arg_builder=gen_arg_builder,
        serde_cls=Serde,
        to_python_type=to_python_type,
        to_cairo_type=to_cairo_type,
        hint_locals={"get_op": get_op},
    )


@pytest.fixture(scope="module")
def cairo_run(request, cairo_program, rust_program, cairo_file, main_path):
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
    if request.node.get_closest_marker("python_vm"):
        return run_python_vm(
            cairo_program,
            cairo_file,
            main_path,
            request,
            gen_arg_builder=gen_arg_builder,
            serde_cls=Serde,
            to_python_type=to_python_type,
            to_cairo_type=to_cairo_type,
            hint_locals={"get_op": get_op},
        )

    return run_rust_vm(
        cairo_program,
        rust_program,
        cairo_file,
        main_path,
        request,
        gen_arg_builder=gen_arg_builder,
        serde_cls=Serde,
        to_python_type=to_python_type,
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

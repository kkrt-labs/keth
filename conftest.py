import logging
import os

import pytest
from dotenv import load_dotenv
from hypothesis import HealthCheck, Phase, Verbosity, settings

load_dotenv()
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger()


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
    """Initialize custom logging for the test suite."""
    init_tracer()


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

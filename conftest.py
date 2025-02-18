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
    derandomize=False,
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

import logging
import os
import shutil
from pathlib import Path

import pytest
from dotenv import load_dotenv
from hypothesis import Phase, Verbosity, settings

from tests.utils.coverage import report_runs
from tests.utils.reporting import dump_coverage

load_dotenv()
logger = logging.getLogger()


@pytest.fixture(autouse=True, scope="session")
def seed(request):
    if request.config.getoption("seed") is not None:
        import random

        logger.info(f"Setting seed to {request.config.getoption('seed')}")

        random.seed(request.config.getoption("seed"))


@pytest.fixture(scope="session", autouse=True)
async def coverage(worker_id):
    yield

    files = report_runs(excluded_file={"site-packages", "tests"})

    output_dir = Path("coverage")
    if worker_id != "master":
        output_dir = output_dir / worker_id

    output_dir.mkdir(exist_ok=True, parents=True)
    shutil.rmtree(output_dir, ignore_errors=True)
    dump_coverage(output_dir, files)


settings.register_profile(
    "nightly",
    deadline=None,
    max_examples=1500,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
)
settings.register_profile(
    "ci",
    deadline=None,
    max_examples=100,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
)
settings.register_profile(
    "dev",
    deadline=None,
    max_examples=10,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
)
settings.register_profile(
    "debug",
    max_examples=10,
    verbosity=Verbosity.verbose,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
)
settings.load_profile(os.getenv("HYPOTHESIS_PROFILE", "default"))
logger.info(f"Using Hypothesis profile: {os.getenv('HYPOTHESIS_PROFILE', 'default')}")

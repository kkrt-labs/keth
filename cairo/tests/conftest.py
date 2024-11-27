import logging
import shutil
from pathlib import Path

import pytest
from dotenv import load_dotenv

from tests.utils.coverage import report_runs
from tests.utils.reporting import dump_coverage
from tests.utils.strategies import register_type_strategies

load_dotenv()
logger = logging.getLogger()
register_type_strategies()


@pytest.fixture(autouse=True, scope="session")
def seed(request):
    if request.config.getoption("seed") is not None:
        import random

        logger.info(f"Setting seed to {request.config.getoption('seed')}")

        random.seed(request.config.getoption("seed"))


@pytest.fixture(scope="session", autouse=True)
def coverage(worker_id, request):
    yield

    if any(p.suffix == ".py" for p in request.node._initialpaths):
        # Skip coverage when running single test files
        return

    files = report_runs(excluded_file={"site-packages", "tests"})

    output_dir = Path("coverage")
    if worker_id != "master":
        output_dir = output_dir / worker_id

    output_dir.mkdir(exist_ok=True, parents=True)
    shutil.rmtree(output_dir, ignore_errors=True)
    dump_coverage(output_dir, files)

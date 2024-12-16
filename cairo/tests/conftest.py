import os

os.environ["PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION"] = "python"

import logging
import os
import shutil
from pathlib import Path

import pytest
import starkware.cairo.lang.instances as LAYOUTS
import xxhash
from dotenv import load_dotenv
from hypothesis import HealthCheck, Phase, Verbosity, settings

from tests.utils.caching import CACHED_TESTS_FILE, program_hash, testfile_hash
from tests.utils.compiler import get_cairo_file, get_cairo_program, get_main_path
from tests.utils.coverage import report_runs
from tests.utils.reporting import dump_coverage
from tests.utils.strategies import register_type_strategies

load_dotenv()
logger = logging.getLogger()


def pytest_addoption(parser):
    parser.addoption(
        "--profile-cairo",
        action="store_true",
        default=False,
        help="compute and dump TracerData for the VM runner: True or False",
    )
    parser.addoption(
        "--proof-mode",
        action="store_true",
        default=False,
        help="run the CairoRunner in proof mode: True or False",
    )
    parser.addoption(
        "--skip-cached-tests",
        action="store_true",
        default=True,
        help="skip tests if neither the cairo program nor the test file has changed: True or False",
    )
    parser.addoption(
        "--no-skip-cached-tests",
        action="store_false",
        dest="skip_cached_tests",
        help="run all tests regardless of cache",
    )
    parser.addoption(
        "--layout",
        choices=dir(LAYOUTS),
        default="all_cairo_instance",
        help="The layout of the Cairo AIR.",
    )
    parser.addoption(
        "--seed",
        action="store",
        default=None,
        type=int,
        help="The seed to set random with.",
    )


pytest_plugins = ["tests.fixtures.runner"]

register_type_strategies()
settings.register_profile(
    "nightly",
    deadline=None,
    max_examples=1500,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
    report_multiple_bugs=True,
    suppress_health_check=[HealthCheck.too_slow],
)
settings.register_profile(
    "ci",
    deadline=None,
    max_examples=100,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
    derandomize=True,
)
settings.register_profile(
    "dev",
    deadline=None,
    max_examples=30,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
    derandomize=True,
)
settings.register_profile(
    "debug",
    max_examples=30,
    verbosity=Verbosity.verbose,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
    derandomize=True,
)
settings.load_profile(os.getenv("HYPOTHESIS_PROFILE", "default"))
logger.info(f"Using Hypothesis profile: {os.getenv('HYPOTHESIS_PROFILE', 'default')}")


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


def pytest_sessionstart(session):
    session.results = dict()


def pytest_sessionfinish(session):
    tests_to_skip = session.config.cache.get(CACHED_TESTS_FILE, [])
    for item in session.results.values():
        if not item.passed:
            continue
        if session.test_hashes[item.nodeid] not in tests_to_skip:
            tests_to_skip.append(session.test_hashes[item.nodeid])

    session.config.cache.set(CACHED_TESTS_FILE, tests_to_skip)


@pytest.hookimpl(tryfirst=True, hookwrapper=True)
def pytest_runtest_makereport(item, call):
    outcome = yield
    result = outcome.get_result()

    if result.when == "call":
        item.session.results[item] = result


@pytest.hookimpl(wrapper=True)
def pytest_collection_modifyitems(session, config, items):
    tests_to_skip = config.cache.get(CACHED_TESTS_FILE, [])
    session.cairo_files = {}
    session.cairo_programs = {}
    session.main_paths = {}
    session.test_hashes = {}
    for item in items:
        if hasattr(item, "fixturenames") and set(item.fixturenames) & {
            "cairo_file",
            "main_path",
            "cairo_program",
            "cairo_run",
        }:
            cairo_file = get_cairo_file(item.fspath)
            session.cairo_files[item.fspath] = cairo_file
            main_path = get_main_path(cairo_file)
            session.main_paths[item.fspath] = main_path
            cairo_program = get_cairo_program(cairo_file, main_path)
            session.cairo_programs[item.fspath] = cairo_program

            test_hash = xxhash.xxh64(
                program_hash(cairo_program)
                + testfile_hash(item.fspath)
                + item.nodeid.encode()
            ).hexdigest()
            session.test_hashes[item.nodeid] = test_hash

            if test_hash in tests_to_skip and config.getoption("skip_cached_tests"):
                item.add_marker(pytest.mark.skip(reason="Cached results"))

    yield

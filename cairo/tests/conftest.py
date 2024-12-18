import logging
import os
import shutil
import time
from dataclasses import fields
from pathlib import Path

import pytest
import starkware.cairo.lang.instances as LAYOUTS
import xdist
import xxhash
from _pytest.mark import deselect_by_keyword, deselect_by_mark
from dotenv import load_dotenv
from hypothesis import HealthCheck, Phase, Verbosity, settings

from tests.utils.caching import CACHED_TESTS_FILE, file_hash, program_hash
from tests.utils.compiler import get_cairo_file, get_cairo_program, get_main_path
from tests.utils.strategies import register_type_strategies

load_dotenv()
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
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
        "--no-skip-mark",
        action="store_true",
        default=False,
        help="Do not skip tests by marked with @pytest.mark.skip",
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
    max_examples=700,
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
    print_blob=True,
    verbosity=Verbosity.quiet,
)
settings.register_profile(
    "debug",
    max_examples=2,
    verbosity=Verbosity.verbose,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
    derandomize=True,
    print_blob=True,
)
settings.load_profile(os.getenv("HYPOTHESIS_PROFILE", "default"))
logger.info(f"Using Hypothesis profile: {os.getenv('HYPOTHESIS_PROFILE', 'default')}")


@pytest.fixture(autouse=True, scope="session")
def seed(request):
    if request.config.getoption("seed") is not None:
        import random

        logger.info(f"Setting seed to {request.config.getoption('seed')}")

        random.seed(request.config.getoption("seed"))


def pytest_sessionstart(session):
    session.results = dict()
    session.build_dir = Path("build") / ".pytest_build"


def pytest_sessionfinish(session):

    if xdist.is_xdist_controller(session):
        logger.info("Controller worker: collecting tests to skip")
        shutil.rmtree(session.build_dir, ignore_errors=True)
        tests_to_skip = session.config.cache.get(f"cairo_run/{CACHED_TESTS_FILE}", [])
        for worker_id in range(session.config.option.numprocesses):
            tests_to_skip += session.config.cache.get(
                f"cairo_run/gw{worker_id}/{CACHED_TESTS_FILE}", []
            )
        session.config.cache.set(f"cairo_run/{CACHED_TESTS_FILE}", tests_to_skip)
        return

    session_tests_to_skip = [
        session.test_hashes[item.nodeid]
        for item in session.results.values()
        if item.passed and item.nodeid in session.test_hashes
    ]

    if xdist.is_xdist_worker(session):
        worker_id = xdist.get_xdist_worker_id(session)
        logger.info(f"Worker {worker_id}: collecting tests to skip")
        session.config.cache.set(
            f"cairo_run/{worker_id}/{CACHED_TESTS_FILE}",
            session_tests_to_skip,
        )
        return

    logger.info("Sequential worker: collecting tests to skip")
    shutil.rmtree(session.build_dir, ignore_errors=True)
    tests_to_skip = session.config.cache.get(f"cairo_run/{CACHED_TESTS_FILE}", [])
    tests_to_skip += session_tests_to_skip
    session.config.cache.set(f"cairo_run/{CACHED_TESTS_FILE}", list(set(tests_to_skip)))


@pytest.hookimpl(tryfirst=True, hookwrapper=True)
def pytest_runtest_makereport(item, call):
    outcome = yield
    result = outcome.get_result()

    if result.when == "call":
        item.session.results[item] = result


def get_dump_path(session, fspath):
    dump_path = session.build_dir / session.cairo_files[fspath].relative_to(
        Path().cwd()
    ).with_suffix(".json")
    dump_path.parent.mkdir(parents=True, exist_ok=True)
    return dump_path


@pytest.hookimpl(wrapper=True)
def pytest_collection_modifyitems(session, config, items):
    # deselect tests by keyword and mark here to avoid compiling cairo files
    deselect_by_keyword(items, config)
    deselect_by_mark(items, config)

    # Collect only is used by the IDE to collect tests, at this point
    # we don't want to compile the cairo files
    if config.option.collectonly:
        yield
        return

    tests_to_skip = config.cache.get(f"cairo_run/{CACHED_TESTS_FILE}", [])
    session.cairo_files = {}
    session.cairo_programs = {}
    session.main_paths = {}
    session.test_hashes = {}
    cairo_items = [
        item
        for item in items
        if (
            hasattr(item, "fixturenames")
            and set(item.fixturenames)
            & {
                "cairo_file",
                "main_path",
                "cairo_program",
                "cairo_run",
            }
        )
    ]

    # Distribute compilation using modulo
    worker_count = getattr(config, "workerinput", {}).get("workercount", 1)
    worker_id = getattr(config, "workerinput", {}).get("workerid", "master")
    worker_index = int(worker_id[2:]) if worker_id != "master" else 0
    fspaths = sorted(list({item.fspath for item in cairo_items}))
    for fspath in fspaths[worker_index::worker_count]:
        session.cairo_files[fspath] = get_cairo_file(fspath)
        session.main_paths[fspath] = get_main_path(session.cairo_files[fspath])
        dump_path = get_dump_path(session, fspath)
        session.cairo_programs[fspath] = get_cairo_program(
            session.cairo_files[fspath],
            session.main_paths[fspath],
            dump_path,
        )

    # Wait for all workers to finish
    missing = set(fspaths) - set(fspaths[worker_index::worker_count])
    while missing:
        logger.info(f"Waiting for {len(missing)} compilations artifacts to be ready")
        missing_new = set()
        for fspath in missing:
            if fspath not in session.cairo_files:
                session.cairo_files[fspath] = get_cairo_file(fspath)
            if fspath not in session.main_paths:
                session.main_paths[fspath] = get_main_path(session.cairo_files[fspath])
            if fspath not in session.cairo_programs:
                dump_path = get_dump_path(session, fspath)
                if dump_path.exists():
                    session.cairo_programs[fspath] = get_cairo_program(
                        session.cairo_files[fspath],
                        session.main_paths[fspath],
                        dump_path,
                    )
                else:
                    missing_new.add(fspath)
        missing = missing_new
        time.sleep(0.25)

    # Select tests
    for item in cairo_items:
        cairo_program = session.cairo_programs[item.fspath]
        test_hash = xxhash.xxh64(
            program_hash(cairo_program)
            + file_hash(item.fspath)
            + item.nodeid.encode()
            + file_hash(Path(__file__).parent / "fixtures" / "runner.py")
            + file_hash(Path(__file__).parent / "utils" / "serde.py")
            + file_hash(Path(__file__).parent / "utils" / "args_gen.py")
            + file_hash(Path(__file__).parent / "utils" / "strategies.py")
        ).hexdigest()
        session.test_hashes[item.nodeid] = test_hash

        if config.getoption("no_skip_mark"):
            item.own_markers = [
                mark for mark in item.own_markers if mark.name != "skip"
            ]

        if test_hash in tests_to_skip and config.getoption("skip_cached_tests"):
            item.add_marker(pytest.mark.skip(reason="Cached results"))

    yield


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

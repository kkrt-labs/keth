"""
Cairo Test System - pytest Hooks

This module provides pytest hooks for the Cairo test system.
"""

import logging
import pickle
import shutil
import time
from multiprocessing import Pool
from pathlib import Path

import pytest
import starkware.cairo.lang.instances as LAYOUTS
import xdist
import xxhash
from _pytest.mark import deselect_by_keyword, deselect_by_mark
from starkware.cairo.lang.compiler.cairo_compile import DEFAULT_PRIME

from cairo_addons.testing.caching import (
    CACHED_TEST_HASH_FILE,
    CACHED_TESTS_FILE,
    CAIRO_DIR_TIMESTAMP_FILE,
    file_hash,
    has_cairo_dir_changed,
    program_hash,
)
from cairo_addons.testing.compiler import (
    get_cairo_program,
    get_main_path,
    resolve_cairo_file,
)

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger()

pytest_plugins = ["cairo_addons.testing.fixtures"]


def parse_int(value):
    """Parse integer from decimal or hex string."""
    if isinstance(value, int):
        return value
    if value.startswith("0x"):
        return int(value, 16)
    return int(value, 10)


def pytest_addoption(parser):
    parser.addoption(
        "--profile-cairo",
        action="store_true",
        default=False,
        help="compute and dump TracerData for the VM runner: True or False",
    )
    parser.addoption(
        "--prime",
        action="store",
        type=parse_int,
        default=DEFAULT_PRIME,
        help="prime to use for the tests",
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


@pytest.fixture(autouse=True, scope="session")
def seed(request):
    if request.config.getoption("seed") is not None:
        import random

        logger.info(f"Setting seed to {request.config.getoption('seed')}")

        random.seed(request.config.getoption("seed"))


def pytest_sessionstart(session):
    session.results = dict()
    session.build_dir = Path("build") / ".pytest_build"

    # Check if any file in the cairo directory has changed since the last run
    last_timestamp = session.config.cache.get(
        f"cairo_run/{CAIRO_DIR_TIMESTAMP_FILE}", 0
    )
    if has_cairo_dir_changed(timestamp=last_timestamp):
        logger.info("Cairo files have changed since last run, clearing build directory")
        shutil.rmtree(session.build_dir, ignore_errors=True)
        session.config.cache.set(f"cairo_run/{CACHED_TEST_HASH_FILE}", None)

    # Store current timestamp for next run
    session.config.cache.set(f"cairo_run/{CAIRO_DIR_TIMESTAMP_FILE}", time.time())


def pytest_sessionfinish(session):
    if xdist.is_xdist_controller(session):
        logger.info("Controller worker: collecting tests to skip")
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
    # Don't clear the build directory to keep compilation artifacts
    tests_to_skip = session.config.cache.get(f"cairo_run/{CACHED_TESTS_FILE}", [])
    tests_to_skip += session_tests_to_skip
    session.config.cache.set(f"cairo_run/{CACHED_TESTS_FILE}", list(set(tests_to_skip)))


@pytest.hookimpl(tryfirst=True, hookwrapper=True)
def pytest_runtest_makereport(item, call):
    outcome = yield
    result = outcome.get_result()

    if result.when == "call":
        item.session.results[item] = result


def get_dump_paths(session, fspath):
    files = session.cairo_files[fspath]
    dump_paths = []
    for file in files:
        dump_path = session.build_dir / file.relative_to(Path().cwd()).with_suffix(
            ".pickle"
        )
        dump_path.parent.mkdir(parents=True, exist_ok=True)
        dump_paths.append(dump_path)
    return dump_paths


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
                "cairo_files",
                "main_paths",
                "cairo_programs",
                "cairo_program",
                "cairo_run",
                "cairo_state_transition",
                "cairo_run_ethereum_tests",
            }
        )
    ]

    logger.info(f"Using prime: 0x{config.getoption('prime'):x}")

    # Distribute compilation using modulo
    worker_count = getattr(config, "workerinput", {}).get("workercount", 1)
    worker_id = getattr(config, "workerinput", {}).get("workerid", "master")
    worker_index = int(worker_id[2:]) if worker_id != "master" else 0
    fspaths = sorted(list({item.fspath for item in cairo_items}))

    for fspath in fspaths[worker_index::worker_count]:
        file_items = [item for item in cairo_items if item.fspath == fspath]
        files = resolve_cairo_file(fspath, file_items[0])
        session.cairo_files[fspath] = files
        main_paths = [get_main_path(file) for file in files]
        session.main_paths[fspath] = main_paths
        dump_paths = get_dump_paths(session, fspath)
        cairo_programs = [
            get_cairo_program(file, main_path, dump_path, config.getoption("prime"))
            for file, main_path, dump_path in zip(files, main_paths, dump_paths)
        ]
        session.cairo_programs[fspath] = cairo_programs

    # Wait for all workers to finish
    missing = set(fspaths) - set(fspaths[worker_index::worker_count])
    while missing:
        logger.info(f"Waiting for {len(missing)} compilations artifacts to be ready")
        missing_new = set()
        for fspath in missing:
            if fspath not in session.cairo_files:
                file_items = [item for item in cairo_items if item.fspath == fspath]
                files = resolve_cairo_file(fspath, file_items[0])
                session.cairo_files[fspath] = files

            if fspath not in session.main_paths:
                session.main_paths[fspath] = [
                    get_main_path(file) for file in session.cairo_files[fspath]
                ]
            if fspath not in session.cairo_programs:
                dump_paths = get_dump_paths(session, fspath)
                # Only proceed when all dump paths exist
                if all(path.exists() for path in dump_paths):
                    cairo_files = session.cairo_files[fspath]
                    main_paths = session.main_paths[fspath]
                    session.cairo_programs[fspath] = [
                        get_cairo_program(
                            cairo_file,
                            main_path,
                            dump_path,
                            config.getoption("prime"),
                        )
                        for cairo_file, main_path, dump_path in zip(
                            cairo_files, main_paths, dump_paths
                        )
                    ]
                else:
                    missing_new.add(fspath)
        missing = missing_new
        time.sleep(0.25)

    # Only worker0 computes test hashes based on the compiled artifacts
    if (
        worker_id == "gw0"
        or worker_id == "master"
        and config.cache.get(f"cairo_run/{CACHED_TEST_HASH_FILE}", None) is None
    ):
        logger.info(f"Worker {worker_id}: Computing test hashes")
        runner_path = Path(__file__).parent / "runner.py"
        args_list = [
            (
                str(item.fspath),
                item.nodeid,
                session.cairo_programs[item.fspath],
                str(runner_path),
            )
            for item in cairo_items
        ]
        with Pool() as pool:
            test_hashes = dict(pool.map(compute_test_hash, args_list))
        config.cache.set(f"cairo_run/{CACHED_TEST_HASH_FILE}", test_hashes)
        session.test_hashes = test_hashes
    else:
        # Load precomputed hashes
        session.test_hashes = config.cache.get(
            f"cairo_run/{CACHED_TEST_HASH_FILE}", None
        )
        while session.test_hashes is None:
            logger.info(f"Worker {worker_id} waiting for test hashes...")
            time.sleep(1)
            session.test_hashes = config.cache.get(
                f"cairo_run/{CACHED_TEST_HASH_FILE}", None
            )

    for item in cairo_items:
        if config.getoption("no_skip_mark"):
            item.own_markers = [
                mark for mark in item.own_markers if mark.name != "skip"
            ]
        if (
            config.getoption("skip_cached_tests")
            and session.test_hashes.get(item.nodeid) in tests_to_skip
        ):
            item.add_marker(pytest.mark.skip(reason="Cached results"))

    yield


def compute_test_hash(args):
    """Compute hash for a single test item using only picklable data"""
    fspath, nodeid, program_data, runner_path = args

    # Hash both main and test programs
    program_hashes = [
        hash_ for program in program_data for hash_ in program_hash(program)
    ]

    test_hash = xxhash.xxh64(
        bytes(program_hashes)
        + file_hash(fspath)
        + nodeid.encode()
        + file_hash(runner_path)
    ).hexdigest()

    return nodeid, test_hash

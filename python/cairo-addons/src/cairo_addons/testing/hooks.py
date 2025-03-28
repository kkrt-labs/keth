"""
Cairo Test System - pytest Hooks

This module provides pytest hooks for the Cairo test system.
"""

import json
import logging
import random
import shutil
import time
from pathlib import Path

import filelock
import pytest
import starkware.cairo.lang.instances as LAYOUTS
import xdist
import xxhash
from _pytest.mark import deselect_by_keyword, deselect_by_mark
from starkware.cairo.lang.compiler.cairo_compile import DEFAULT_PRIME

from cairo_addons.testing.caching import (
    BUILD_DIR,
    CACHED_TEST_HASH_FILE,
    CACHED_TESTS_FILE,
    CAIRO_DIR_TIMESTAMP_FILE,
    HASH_DIR,
    file_hash,
    get_dump_path,
    has_cairo_dir_changed,
    program_hash,
)
from cairo_addons.testing.compiler import (
    get_cairo_program,
    get_main_path,
    resolve_cairo_file,
)
from cairo_addons.testing.coverage import dump_coverage_dataframes

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
    parser.addoption(
        "--no-coverage",
        action="store_true",
        default=False,
        help="Do not collect coverage",
    )


@pytest.fixture(autouse=True, scope="session")
def seed(request):
    if request.config.getoption("seed") is not None:
        import random

        logger.info(f"Setting seed to {request.config.getoption('seed')}")

        random.seed(request.config.getoption("seed"))


def pytest_sessionstart(session):
    session.results = dict()
    session.build_dir = BUILD_DIR
    session.hash_dir = HASH_DIR

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

    # Clear hash directory if it exists
    if session.hash_dir.exists():
        shutil.rmtree(session.hash_dir, ignore_errors=True)


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

    # Clear hash directory if it exists
    if session.hash_dir.exists():
        shutil.rmtree(session.hash_dir, ignore_errors=True)


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
        dump_path = get_dump_path(file)
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
    session.coverage_dataframes = {}
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

    # Get random seed from CLI arg and shuffle tests
    seed = getattr(config.option, "randomly_seed", None)
    if seed is not None:
        random.seed(seed)
        random.shuffle(cairo_items)
        logger.info(f"Shuffling tests with seed {seed}")

    # Handle max-tests option if provided
    max_tests = getattr(config.option, "max_tests", None)
    if max_tests is not None and len(cairo_items) > max_tests:
        logger.info(
            f"Running {max_tests} tests out of {len(cairo_items)} available tests"
        )
        cairo_items = cairo_items[:max_tests]
        items[:] = cairo_items

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
        cairo_programs = []
        for file, main_path, dump_path in zip(files, main_paths, dump_paths):
            cairo_program = get_cairo_program(
                file, main_path, dump_path, config.getoption("prime")
            )
            cairo_programs.append(cairo_program)
            if not config.getoption("no_coverage"):
                dump_coverage_dataframes(cairo_program, file, dump_path)
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
                    cairo_programs = []
                    for cairo_file, main_path, dump_path in zip(
                        cairo_files, main_paths, dump_paths
                    ):
                        cairo_program = get_cairo_program(
                            cairo_file,
                            main_path,
                            dump_path,
                            config.getoption("prime"),
                        )
                        cairo_programs.append(cairo_program)
                        if not config.getoption("no_coverage"):
                            dump_coverage_dataframes(
                                cairo_program, cairo_file, dump_path
                            )
                    session.cairo_programs[fspath] = cairo_programs
                else:
                    missing_new.add(fspath)
        missing = missing_new
        time.sleep(0.25)

    # Create a shared directory for hash files
    # Define the single hash file for all workers
    hash_dir = session.build_dir / "hashes"
    hash_dir.mkdir(parents=True, exist_ok=True)
    hash_file = hash_dir / "all_hashes.json"
    hash_file_lock = filelock.FileLock(str(hash_file) + ".lock")

    # Compute hashes for this worker's assigned items
    total_items = len(cairo_items)
    assigned_items = cairo_items[worker_index::worker_count]
    runner_path = Path(__file__).parent / "runner.py"
    logger.info(f"{worker_id}: Computing {len(assigned_items)} test hashes")

    worker_hashes = {}
    for item in assigned_items:
        args = (
            str(item.fspath),
            item.nodeid,
            session.cairo_programs[item.fspath],
            str(runner_path),
        )
        test_hash = compute_test_hash(args)
        worker_hashes[item.nodeid] = test_hash

    # Append this worker's hashes to the shared file with lock
    with hash_file_lock:
        all_hashes = {}
        if hash_file.exists():
            try:
                with hash_file.open("r") as f:
                    all_hashes = json.load(f)
            except json.JSONDecodeError:
                logger.error(f"{worker_id}: Error reading hash file, starting fresh")
                all_hashes = {}

        # Update with this worker's hashes
        all_hashes.update(worker_hashes)

        # Write back the updated hashes
        with hash_file.open("w") as f:
            json.dump(all_hashes, f)

        # Log progress
        current_hashes = len(all_hashes)
        logger.info(
            f"{worker_id}: Added {len(worker_hashes)} hashes, total now {current_hashes}/{total_items}"
        )

    # Wait until all hashes are computed
    start_time = time.time()
    timeout = 300  # 5 minutes timeout
    while time.time() - start_time < timeout:
        with hash_file_lock:
            if hash_file.exists():
                try:
                    with hash_file.open("r") as f:
                        all_hashes = json.load(f)
                    if len(all_hashes) >= total_items:
                        logger.info(
                            f"{worker_id}: All {len(all_hashes)} hashes collected, continuing"
                        )
                        break
                except json.JSONDecodeError:
                    logger.error(f"{worker_id}: Error reading hash file during wait")

        time.sleep(1)

    # Load all hashes for this session
    with hash_file_lock:
        try:
            with hash_file.open("r") as f:
                session.test_hashes = json.load(f)
        except json.JSONDecodeError as e:
            logger.error(f"{worker_id}: Error reading complete hash file: {e}")
            session.test_hashes = {}

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

    return test_hash

import os
import shutil
import tarfile
from pathlib import Path
from typing import Final, Optional, Set

import git
import requests_cache
from _pytest.config.argparsing import Parser
from filelock import FileLock
from git.exc import GitCommandError, InvalidGitRepositoryError
from pytest import Session, StashKey
from requests_cache import CachedSession
from requests_cache.backends.sqlite import SQLiteCache
from typing_extensions import Self
from xdist import get_xdist_worker_id

from tests.ef_tests.helpers import TEST_FIXTURES


def pytest_addoption(parser: Parser) -> None:
    """Add custom command-line options to pytest."""
    parser.addoption(
        "--max-tests",
        action="store",
        type=int,
        help="Maximum number of EF tests to run in sampled mode.",
    )


class _FixturesDownloader:
    cache: Final[SQLiteCache]
    session: Final[CachedSession]
    root: Final[Path]
    keep_cache_keys: Final[Set[str]]

    def __init__(self, root: Path) -> None:
        self.root = root
        self.cache = SQLiteCache(use_cache_dir=True, db_path="eels_cache")
        self.session = requests_cache.CachedSession(
            backend=self.cache,
            ignored_parameters=["X-Amz-Signature", "X-Amz-Date"],
            expire_after=24 * 60 * 60,
            cache_control=True,
        )
        self.keep_cache_keys = set()

    def fetch_http(self, url: str, location: str) -> None:
        path = self.root.joinpath(location)
        print(f"Downloading {location}...")

        with self.session.get(url, stream=True) as response:
            if response.from_cache:
                print(f"Cache hit {url}")
            else:
                print(f"Cache miss {url} :(")

            # Track the cache keys we've hit this session so we don't delete
            # them.
            all_responses = [response] + response.history
            current_keys = set(
                self.cache.create_key(request=r.request) for r in all_responses
            )
            self.keep_cache_keys.update(current_keys)

            with tarfile.open(fileobj=response.raw, mode="r:gz") as tar:
                shutil.rmtree(path, ignore_errors=True)
                print(f"Extracting {location}...")
                tar.extractall(path)

    def fetch_git(self, url: str, location: str, commit_hash: str) -> None:
        path = self.root.joinpath(location)
        if not os.path.exists(path):
            print(f"Cloning {location}...")
            repo = git.Repo.clone_from(url, to_path=path)
        else:
            print(f"{location} already available.")
            repo = git.Repo(path)

        print(f"Checking out the correct commit {commit_hash}...")
        branch = repo.heads["develop"]
        # Try to checkout the relevant commit hash and if that fails
        # fetch the latest changes and checkout the commit hash
        try:
            repo.git.checkout(commit_hash)
        except GitCommandError:
            repo.remotes.origin.fetch(branch.name)
            repo.git.checkout(commit_hash)

        # Check if the submodule head matches the parent commit
        # If not, update the submodule
        for submodule in repo.submodules:
            # Initialize the submodule if not already initialized
            try:
                submodule_repo = submodule.module()
            except InvalidGitRepositoryError:
                submodule.update(init=True, recursive=True)
                continue

            # Commit expected by the parent repo
            parent_commit = submodule.hexsha

            # Actual submodule head
            submodule_head = submodule_repo.head.commit.hexsha
            if parent_commit != submodule_head:
                submodule.update(init=True, recursive=True)

    def __enter__(self) -> Self:
        assert not self.keep_cache_keys
        return self

    def __exit__(self, exc_type: object, exc_value: object, traceback: object) -> None:
        cached = self.cache.filter(expired=True, invalid=True)
        to_delete = set(x.cache_key for x in cached) - self.keep_cache_keys
        if to_delete:
            print(f"Evicting {len(to_delete)} from HTTP cache")
            self.cache.delete(*to_delete, vacuum=True)
        self.keep_cache_keys.clear()


fixture_lock = StashKey[Optional[FileLock]]()


def pytest_sessionstart(session: Session) -> None:  # noqa: U100
    if get_xdist_worker_id(session) != "master":
        return

    lock_path = session.config.rootpath.joinpath("tests/fixtures/.lock")
    stash = session.stash
    lock_file = FileLock(str(lock_path), timeout=0)
    lock_file.acquire()

    assert fixture_lock not in stash
    stash[fixture_lock] = lock_file

    with _FixturesDownloader(session.config.rootpath) as downloader:
        for _, props in TEST_FIXTURES.items():
            fixture_path = props["fixture_path"]

            os.makedirs(os.path.dirname(fixture_path), exist_ok=True)

            if "commit_hash" in props:
                downloader.fetch_git(props["url"], fixture_path, props["commit_hash"])
            else:
                downloader.fetch_http(
                    props["url"],
                    fixture_path,
                )


def pytest_sessionfinish(session: Session, exitstatus: int) -> None:  # noqa: U100
    if get_xdist_worker_id(session) != "master":
        return

    lock_file_obj: Optional[FileLock] = session.stash.get(fixture_lock, None)

    if lock_file_obj is not None:
        try:
            lock_file_obj.release()
        except Exception as e:
            print(f"ERROR: Failed to release fixture lock: {e}")
        finally:
            # Ensure the key is removed or nulled from stash
            if fixture_lock in session.stash:
                # Match original behavior of setting to None
                session.stash[fixture_lock] = None
                lock_file_obj.release()

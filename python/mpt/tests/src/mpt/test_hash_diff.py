from typing import List

from hypothesis import given

from cairo_addons.rust_bindings.vm import blake2s_hash_many
from tests.utils.args_gen import AddressAccountDiffEntry, StorageDiffEntry


class TestHashEntry:
    @given(account_diff=...)
    def test_hash_account_diff(self, cairo_run, account_diff: AddressAccountDiffEntry):
        cairo_result = cairo_run(
            "hash_account_diff",
            account_diff,
        )
        assert cairo_result == account_diff.hash_cairo()

    @given(storage_diff=...)
    def test_hash_storage_diff(self, cairo_run, storage_diff: StorageDiffEntry):
        cairo_result = cairo_run(
            "hash_storage_diff",
            storage_diff,
        )
        assert cairo_result == storage_diff.hash_cairo()


class TestHashTrieDiff:
    @given(account_diff=...)
    def test_hash_account_diff_segment(
        self, cairo_run, account_diff: List[AddressAccountDiffEntry]
    ):
        cairo_result = cairo_run(
            "hash_account_diff_segment",
            account_diff,
        )
        hashes_buffer = [diff.hash_cairo() for diff in account_diff]
        final_hash = blake2s_hash_many(hashes_buffer)
        assert cairo_result == final_hash

    @given(storage_diff=...)
    def test_hash_storage_diff_segment(
        self, cairo_run, storage_diff: List[StorageDiffEntry]
    ):
        cairo_result = cairo_run(
            "hash_storage_diff_segment",
            storage_diff,
        )
        hashes_buffer = [diff.hash_cairo() for diff in storage_diff]
        final_hash = blake2s_hash_many(hashes_buffer)
        assert cairo_result == final_hash


class TestHashStateDiff:
    @given(state_diff=...)
    def test_hash_state_diff(
        self, cairo_run, state_diff: List[AddressAccountDiffEntry]
    ):
        # Note: we can't generate data in the proper format using args gen.
        # What we do is generate a list of AddressAccountDiffEntry, and then
        # in cairo, we'll convert it to the proper format in a segment of sequential DictAccess.
        cairo_result = cairo_run(
            "test_hash_state_diff",
            state_diff,
        )
        # Eliminate non-diff entries from the python expected result
        state_diff_filtered = [
            diff for diff in state_diff if diff.prev_value != diff.new_value
        ]

        hashes_buffer = [diff.hash_cairo() for diff in state_diff_filtered]
        final_hash = blake2s_hash_many(hashes_buffer)
        assert cairo_result == final_hash

    @given(storage_diff=...)
    def test_hash_storage_diff(self, cairo_run, storage_diff: List[StorageDiffEntry]):
        # Note: we can't generate data in the proper format using args gen.
        # What we do is generate a list of StorageDiffEntry, and then
        # in cairo, we'll convert it to the proper format in a segment of sequential DictAccess.
        cairo_result = cairo_run(
            "test_hash_storage_diff",
            storage_diff,
        )

        # Eliminate non-diff entries from the python expected result
        storage_diff_filtered = [
            diff for diff in storage_diff if diff.prev_value != diff.new_value
        ]

        hashes_buffer = [diff.hash_cairo() for diff in storage_diff_filtered]
        final_hash = blake2s_hash_many(hashes_buffer)
        assert cairo_result == final_hash

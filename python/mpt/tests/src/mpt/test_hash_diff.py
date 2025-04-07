from typing import List

from hypothesis import given
from starkware.cairo.lang.vm.crypto import poseidon_hash_many

from tests.utils.args_gen import AddressAccountDiffEntry, StorageDiffEntry


class TestHashDiff:
    @given(account_diff=...)
    def test_poseidon_account_diff(
        self, cairo_run, account_diff: AddressAccountDiffEntry
    ):
        cairo_result = cairo_run(
            "poseidon_account_diff",
            account_diff,
        )
        assert cairo_result == account_diff.hash_poseidon()

    @given(storage_diff=...)
    def test_poseidon_storage_diff(self, cairo_run, storage_diff: StorageDiffEntry):
        cairo_result = cairo_run(
            "poseidon_storage_diff",
            storage_diff,
        )
        assert cairo_result == storage_diff.hash_poseidon()

    @given(account_diff=...)
    def test_hash_account_diff_segment(
        self, cairo_run, account_diff: List[AddressAccountDiffEntry]
    ):
        cairo_result = cairo_run(
            "hash_account_diff_segment",
            account_diff,
        )
        if len(account_diff) == 0:
            assert cairo_result == 0
        else:
            acc = account_diff[0].hash_poseidon()
            for diff in account_diff[1:]:
                acc = poseidon_hash_many([acc, diff.hash_poseidon()])
            assert cairo_result == acc

    @given(storage_diff=...)
    def test_hash_storage_diff_segment(
        self, cairo_run, storage_diff: List[StorageDiffEntry]
    ):
        cairo_result = cairo_run(
            "hash_storage_diff_segment",
            storage_diff,
        )
        if len(storage_diff) == 0:
            assert cairo_result == 0
        else:
            acc = storage_diff[0].hash_poseidon()
            for diff in storage_diff[1:]:
                acc = poseidon_hash_many([acc, diff.hash_poseidon()])
            assert cairo_result == acc

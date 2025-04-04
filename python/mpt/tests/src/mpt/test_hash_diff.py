from hypothesis import given

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

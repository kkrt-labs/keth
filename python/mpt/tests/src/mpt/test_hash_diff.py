from hypothesis import given
from starkware.cairo.lang.vm.crypto import poseidon_hash_many

from cairo_addons.utils.uint256 import int_to_uint256
from tests.utils.args_gen import AddressAccountNodeDiffEntry, StorageDiffEntry


class TestHashDiff:
    @given(account_diff=...)
    def test_poseidon_account_diff(
        self, cairo_run, account_diff: AddressAccountNodeDiffEntry
    ):
        cairo_result = cairo_run(
            "poseidon_account_diff",
            account_diff,
        )
        assert cairo_result == poseidon_hash_many(
            [
                int.from_bytes(account_diff.key, "little"),
                *account_diff.prev_value.flatten(),
                *account_diff.new_value.flatten(),
            ]
        )

    @given(storage_diff=...)
    def test_poseidon_storage_diff(self, cairo_run, storage_diff: StorageDiffEntry):
        cairo_result = cairo_run(
            "poseidon_storage_diff",
            storage_diff,
        )
        assert cairo_result == poseidon_hash_many(
            [
                storage_diff.key._number,
                *int_to_uint256(storage_diff.prev_value._number),
                *int_to_uint256(storage_diff.new_value._number),
            ]
        )

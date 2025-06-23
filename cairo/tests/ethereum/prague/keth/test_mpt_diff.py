from pathlib import Path

import pytest

from mpt.ethereum_tries import EthereumTrieTransitionDB
from mpt.trie_diff import StateDiff, compute_commitment
from utils.fixture_loader import (
    load_teardown_input,
    load_zkpi_fixture,
)

pytestmark = pytest.mark.cairo_file(
    f"{Path().cwd()}/cairo/tests/ethereum/prague/keth/test_mpt_diff.cairo",
)


@pytest.fixture
def program_input(zkpi_path):
    return load_zkpi_fixture(zkpi_path)


class TestMptDiff:
    @pytest.mark.parametrize(
        "zkpi_path",
        [Path("test_data/22615247.json")],
    )
    def test_mpt_diff(self, cairo_run, cairo_program, zkpi_path, program_input):
        """
        Tests the mpt_diff program for all branches.
        """

        tries = EthereumTrieTransitionDB.from_json(zkpi_path)

        teardown_input = load_teardown_input(zkpi_path)
        account_diffs = []
        storage_diffs = []
        prev_account_diff_commitment = compute_commitment(account_diffs)
        prev_storage_diff_commitment = compute_commitment(storage_diffs)

        for i in range(16):
            if i != 0:
                input_to_step = StateDiff.from_tries_and_branch_index(tries, i - 1)
                local_account_diffs, local_storage_diffs = (
                    input_to_step.get_diff_segments()
                )
                account_diffs.extend(local_account_diffs)
                storage_diffs.extend(local_storage_diffs)
                account_diffs = sorted(
                    account_diffs, key=lambda x: int.from_bytes(x.key, "little")
                )
                storage_diffs = sorted(storage_diffs, key=lambda x: x.key)

            program_input = {
                **teardown_input,
                "branch_index": i,
                "input_trie_account_diff": account_diffs,
                "input_trie_storage_diff": storage_diffs,
            }
            # TODO: verify the branch hashes at some point.
            (
                input_trie_account_diff_commitment,
                input_trie_storage_diff_commitment,
                branch_index,
                left_hash_low,
                left_hash_high,
                right_hash_low,
                right_hash_high,
                account_diff_commitment,
                storage_diff_commitment,
            ) = cairo_run("test_mpt_diff", verify_squashed_dicts=True, **program_input)

            # The input to the program must be the hash of what we gave it.
            assert input_trie_account_diff_commitment == prev_account_diff_commitment, (
                f"Input account diff commitment mismatch at branch {i}: "
                f"expected {prev_account_diff_commitment}, got {input_trie_account_diff_commitment}"
            )
            assert input_trie_storage_diff_commitment == prev_storage_diff_commitment, (
                f"Input storage diff commitment mismatch at branch {i}: "
                f"expected {prev_storage_diff_commitment}, got {input_trie_storage_diff_commitment}"
            )
            assert (
                branch_index == i
            ), f"Branch index mismatch: expected {i}, got {branch_index}"

            prev_account_diff_commitment = account_diff_commitment
            prev_storage_diff_commitment = storage_diff_commitment

        expected_account_diff_commitment, expected_storage_diff_commitment = (
            StateDiff.from_tries(tries).compute_commitments()
        )
        assert account_diff_commitment == expected_account_diff_commitment
        assert storage_diff_commitment == expected_storage_diff_commitment

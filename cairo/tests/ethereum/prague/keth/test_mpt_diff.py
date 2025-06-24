from pathlib import Path

import pytest
from hypothesis import given
from hypothesis import strategies as st

from mpt.ethereum_tries import EthereumTrieTransitionDB
from mpt.trie_diff import StateDiff, compute_commitment
from utils.fixture_loader import (
    load_mpt_diff_input,
    load_zkpi_fixture,
)

pytestmark = pytest.mark.cairo_file(
    f"{Path().cwd()}/cairo/tests/ethereum/prague/keth/test_mpt_diff.cairo",
)


def run_mpt_diff_branch(zkpi_path, branch_index, cairo_run):
    """
    Runs MPT diff for a single branch and returns the output.

    Args:
        zkpi_path: Path to the ZKPI fixture
        branch_index: Branch index to process (0-15)
        cairo_run: Cairo run function from pytest fixture

    Returns:
        Tuple of MPT diff outputs
    """
    program_input = load_mpt_diff_input(
        zkpi_path=zkpi_path, branch_index=branch_index, previous_outputs_path=None
    )

    return cairo_run("test_mpt_diff", verify_squashed_dicts=True, **program_input)


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

        prev_account_diff_commitment = compute_commitment([])
        prev_storage_diff_commitment = compute_commitment([])

        for i in range(16):
            # TODO: verify the branch hashes at some point.
            program_input = load_mpt_diff_input(
                zkpi_path=zkpi_path,
                branch_index=branch_index,
                previous_outputs_path=None,
            )

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

    @pytest.mark.parametrize("zkpi_path", [Path("test_data/22615247.json")])
    @given(branch_idx=st.integers(min_value=0, max_value=15))
    def test_mpt_diff_single_branch(self, cairo_run, zkpi_path, branch_idx):
        """
        Tests the mpt_diff program for a single branch.
        Useful for debugging specific branch issues.
        """
        # Run the Cairo program for this branch
        program_input = load_mpt_diff_input(
            zkpi_path=zkpi_path,
            branch_index=branch_idx,
        )

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

        # Verify the branch index matches
        assert (
            branch_index == branch_idx
        ), f"Branch index mismatch: expected {branch_idx}, got {branch_index}"

        # Verify commitments are non-zero (basic sanity check)
        assert (
            account_diff_commitment != 0 or storage_diff_commitment != 0
        ), f"Both commitments are zero for branch {branch_idx}"

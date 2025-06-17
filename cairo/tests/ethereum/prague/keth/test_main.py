from pathlib import Path

import pytest

from mpt.trie_diff import StateDiff
from utils.fixture_loader import load_zkpi_fixture

pytestmark = pytest.mark.cairo_file(
    f"{Path().cwd()}/cairo/tests/ethereum/prague/keth/test_e2e.cairo"
)


@pytest.fixture
def program_input(zkpi_path):
    return load_zkpi_fixture(zkpi_path)


class TestMain:
    @pytest.mark.parametrize(
        "zkpi_path",
        [Path("test_data/22615247.json")],
    )
    @pytest.mark.slow
    def test_main(self, cairo_run, zkpi_path, program_input):
        state_diff = StateDiff.from_json(zkpi_path)
        (
            expected_state_account_diff_commitment,
            expected_state_storage_diff_commitment,
        ) = state_diff.compute_commitments()
        expected_pre_state_root = (
            program_input["blockchain"].blocks[-1].header.state_root
        )

        [
            pre_state_root_low,
            pre_state_root_high,
            state_account_diff_commitment,
            state_storage_diff_commitment,
            trie_account_diff_commitment,
            trie_storage_diff_commitment,
        ] = cairo_run("test_main", verify_squashed_dicts=True, **program_input)

        # Program input
        actual_pre_state_root = pre_state_root_low.to_bytes(
            16, "little"
        ) + pre_state_root_high.to_bytes(16, "little")
        assert actual_pre_state_root == expected_pre_state_root

        # Computed in Cairo
        assert state_account_diff_commitment == expected_state_account_diff_commitment
        assert state_storage_diff_commitment == expected_state_storage_diff_commitment
        assert trie_account_diff_commitment == expected_state_account_diff_commitment
        assert trie_storage_diff_commitment == expected_state_storage_diff_commitment

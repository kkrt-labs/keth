from pathlib import Path

import pytest

from utils.fixture_loader import load_teardown_input

pytestmark = pytest.mark.cairo_file(
    f"{Path().cwd()}/cairo/tests/ethereum/cancun/keth/test_e2e.cairo"
)


class TestTeardown:
    @pytest.mark.parametrize(
        "zkpi_path",
        [
            Path("test_data/22188088.json"),
        ],
    )
    @pytest.mark.slow
    def test_teardown(self, cairo_run, zkpi_path):
        # Run all transactions of the body
        teardown_input = load_teardown_input(zkpi_path)
        (
            teardown_commitment_low,
            teardown_commitment_high,
            body_commitment_low,
            body_commitment_high,
        ) = cairo_run("test_teardown", verify_squashed_dicts=True, **teardown_input)

        assert teardown_commitment_low
        assert teardown_commitment_high
        assert body_commitment_low
        assert body_commitment_high

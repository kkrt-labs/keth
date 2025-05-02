from pathlib import Path

import pytest

from utils.fixture_loader import load_teardown_input, load_zkpi_fixture

pytestmark = pytest.mark.cairo_file(
    f"{Path().cwd()}/cairo/tests/ethereum/cancun/keth/test_e2e.cairo",
)


@pytest.fixture
def program_input(zkpi_path):
    return load_zkpi_fixture(zkpi_path)


class TestE2E:
    @pytest.mark.parametrize(
        "zkpi_path",
        [Path("test_data/22188088.json")],
    )
    @pytest.mark.slow
    def test_e2e(self, cairo_run, zkpi_path, program_input):
        [
            body_commitment_low,
            body_commitment_high,
            init_commitment_low,
            init_commitment_high,
        ] = cairo_run("test_init", verify_squashed_dicts=True, **program_input)

        teardown_input = load_teardown_input(zkpi_path)
        (
            teardown_commitment_low,
            teardown_commitment_high,
            body_commitment_low,
            body_commitment_high,
        ) = cairo_run("test_teardown", verify_squashed_dicts=True, **teardown_input)

        assert init_commitment_low == teardown_commitment_low
        assert init_commitment_high == teardown_commitment_high

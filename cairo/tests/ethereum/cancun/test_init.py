from pathlib import Path

import pytest

from utils.fixture_loader import load_zkpi_fixture

pytestmark = pytest.mark.cairo_file(
    f"{Path().cwd()}/cairo/tests/ethereum/cancun/test_init.cairo"
)


@pytest.fixture
def program_input(zkpi_path):
    return load_zkpi_fixture(zkpi_path)


class TestInit:
    @pytest.mark.parametrize(
        "zkpi_path",
        [Path("test_data/22188088.json")],
    )
    @pytest.mark.slow
    def test_init(self, cairo_run, zkpi_path, program_input):
        [
            body_commitment_low,
            body_commitment_high,
            teardown_commitment_low,
            teardown_commitment_high,
        ] = cairo_run("test_init", verify_squashed_dicts=True, **program_input)

        assert body_commitment_low
        assert body_commitment_high
        assert teardown_commitment_low
        assert teardown_commitment_high

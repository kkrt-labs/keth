from pathlib import Path

import pytest
from ethereum_types.numeric import U64

from utils.fixture_loader import load_body_input, load_teardown_input, load_zkpi_fixture

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
            init_body_commitment_low,
            init_body_commitment_high,
            init_teardown_commitment_low,
            init_teardown_commitment_high,
        ] = cairo_run("test_init", verify_squashed_dicts=True, **program_input)

        body_input = load_body_input(zkpi_path, 0, int(U64.MAX_VALUE))
        [
            body_init_commitment_low,
            body_init_commitment_high,
            body_teardown_commitment_low,
            body_teardown_commitment_high,
            body_start_index,
            body_len,
        ] = cairo_run("test_body", verify_squashed_dicts=True, **body_input)

        teardown_input = load_teardown_input(zkpi_path)
        [
            teardown_init_commitment_low,
            teardown_init_commitment_high,
            teardown_body_commitment_low,
            teardown_body_commitment_high,
        ] = cairo_run("test_teardown", verify_squashed_dicts=True, **teardown_input)

        assert body_start_index == 0
        assert body_len == len(body_input["block_transactions"])
        assert init_body_commitment_low == body_init_commitment_low
        assert init_body_commitment_high == body_init_commitment_high
        assert body_teardown_commitment_low == teardown_body_commitment_low
        assert body_teardown_commitment_high == teardown_body_commitment_high
        assert init_teardown_commitment_low == teardown_init_commitment_low
        assert init_teardown_commitment_high == teardown_init_commitment_high

from pathlib import Path

import pytest
from ethereum_types.numeric import U64

from utils.fixture_loader import load_body_input

pytestmark = pytest.mark.cairo_file(
    f"{Path().cwd()}/cairo/tests/ethereum/cancun/keth/test_body.cairo"
)


class TestMain:
    @pytest.mark.parametrize(
        "zkpi_path",
        [Path("test_data/22188088.json")],
    )
    @pytest.mark.slow
    def test_body(self, cairo_run, zkpi_path):
        # Run all transactions of the body
        body_input = load_body_input(
            zkpi_path=zkpi_path, start_index=0, chunk_size=int(U64.MAX_VALUE)
        )
        (
            initial_args_commitment_low,
            initial_args_commitment_high,
            post_exec_commitment_low,
            post_exec_commitment_high,
            start_index,
            len_,
        ) = cairo_run("test_body", verify_squashed_dicts=True, **body_input)

        assert initial_args_commitment_low
        assert initial_args_commitment_high
        assert post_exec_commitment_low
        assert post_exec_commitment_high
        assert start_index == 0
        assert len_ == min(int(U64.MAX_VALUE), len(body_input["block_transactions"]))

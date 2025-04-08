from pathlib import Path

import pytest
from scripts.prove_block import load_zkpi_fixture


@pytest.fixture
def program_input(zkpi_path):
    return load_zkpi_fixture(zkpi_path)


class TestMain:
    @pytest.mark.parametrize(
        "zkpi_path",
        [Path("test_data/22188088.json")],
    )
    @pytest.mark.slow
    def test_main(self, cairo_run, program_input):
        cairo_run("main", **program_input)

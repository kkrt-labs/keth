from pathlib import Path

import pytest
from ethereum.prague.fork import state_transition
from ethereum.exceptions import InvalidBlock
from ethereum_types.numeric import U64
from starkware.cairo.bootloaders.hash_program import compute_program_hash_chain

from cairo_addons.testing.utils import flatten
from utils.fixture_loader import (
    load_body_input,
    load_teardown_input,
    load_zkpi_fixture,
    zkpi_fixture_eels_compatible,
)

pytestmark = pytest.mark.cairo_file(
    f"{Path().cwd()}/cairo/tests/ethereum/prague/keth/test_e2e.cairo",
)


@pytest.fixture
def program_input(zkpi_path):
    return load_zkpi_fixture(zkpi_path)


class TestE2E:
    @pytest.mark.parametrize(
        "zkpi_path",
        [Path("test_data/22188102.json")],
    )
    def test_e2e_eels(self, zkpi_path):
        """
        This test should fail with InvalidBlock exception,
        because we only compute the partial state root.
        This is still useful to test that we have e.g. same gas consumptions.
        """
        eels_program_input = zkpi_fixture_eels_compatible(zkpi_path)
        block = eels_program_input["block"]
        blockchain = eels_program_input["blockchain"]

        with pytest.raises(InvalidBlock):
            state_transition(blockchain, block)

    @pytest.mark.parametrize(
        "zkpi_path",
        [Path("test_data/22188088.json")],
    )
    def test_e2e(self, cairo_run, cairo_program, zkpi_path, program_input):
        """
        Tests the end-to-end flow:
        1. Runs init, body (x2), teardown segments.
        2. Checks commitments match in Python.
        3. Runs the Cairo aggregator with segment outputs.
        4. Verifies the aggregator output format and content.
        """
        # Assuming cairo_program fixture provides the compiled program
        # If init, body, teardown, aggregator are DIFFERENT programs,
        # we'll use separate hashes.
        cairo_test_program_hash = compute_program_hash_chain(
            program=cairo_program, use_poseidon=True
        )

        [
            init_body_commitment_low,
            init_body_commitment_high,
            init_teardown_commitment_low,
            init_teardown_commitment_high,
        ] = init_output = cairo_run(
            "test_init", verify_squashed_dicts=True, **program_input
        )

        transactions_len = len(program_input["block"].transactions)
        first_half_body_input = load_body_input(zkpi_path, 0, transactions_len // 2)
        [
            first_half_body_pre_exec_commitment_low,
            first_half_body_pre_exec_commitment_high,
            first_half_body_post_exec_commitment_low,
            first_half_body_post_exec_commitment_high,
        ] = first_half_body_output = cairo_run(
            "test_body", verify_squashed_dicts=True, **first_half_body_input
        )

        second_half_body_input = load_body_input(
            zkpi_path,
            transactions_len // 2,
            transactions_len - transactions_len // 2,
        )
        [
            second_half_body_pre_exec_commitment_low,
            second_half_body_pre_exec_commitment_high,
            second_half_body_post_exec_commitment_low,
            second_half_body_post_exec_commitment_high,
        ] = second_half_body_output = cairo_run(
            "test_body", verify_squashed_dicts=True, **second_half_body_input
        )

        teardown_input = load_teardown_input(zkpi_path)
        [
            teardown_init_commitment_low,
            teardown_init_commitment_high,
            teardown_body_commitment_low,
            teardown_body_commitment_high,
        ] = teardown_output = cairo_run(
            "test_teardown", verify_squashed_dicts=True, **teardown_input
        )

        # glue init to the first half of the body
        assert init_body_commitment_low == first_half_body_pre_exec_commitment_low
        assert init_body_commitment_high == first_half_body_pre_exec_commitment_high

        # glue the first half of the body to the second half of the body
        assert (
            first_half_body_post_exec_commitment_low
            == second_half_body_pre_exec_commitment_low
        )
        assert (
            first_half_body_post_exec_commitment_high
            == second_half_body_pre_exec_commitment_high
        )

        # glue the second half of the body to the teardown
        assert second_half_body_post_exec_commitment_low == teardown_body_commitment_low
        assert (
            second_half_body_post_exec_commitment_high == teardown_body_commitment_high
        )

        # glue init to the teardown
        assert init_teardown_commitment_low == teardown_init_commitment_low
        assert init_teardown_commitment_high == teardown_init_commitment_high

        # --- Run Cairo Aggregator ---
        # Prepare input for the aggregator Cairo function
        aggregator_input = {
            "keth_segment_outputs": [
                init_output,
                first_half_body_output,
                second_half_body_output,
                teardown_output,
            ],
            "keth_segment_program_hashes": {
                # If they were separate programs, we'd use their respective hashes.
                "init": cairo_test_program_hash,
                "body": cairo_test_program_hash,
                "teardown": cairo_test_program_hash,
            },
            "n_body_chunks": 2,
        }

        aggregator_output = cairo_run(
            "test_aggregator", verify_squashed_dicts=True, **aggregator_input
        )

        TASK_OUTPUT_HEADER_SIZE = 2

        expected_aggregator_output = flatten(
            [
                (TASK_OUTPUT_HEADER_SIZE + len(init_output), cairo_test_program_hash),
                init_output,
                (
                    TASK_OUTPUT_HEADER_SIZE + len(first_half_body_output),
                    cairo_test_program_hash,
                ),
                first_half_body_output,
                (
                    TASK_OUTPUT_HEADER_SIZE + len(second_half_body_output),
                    cairo_test_program_hash,
                ),
                second_half_body_output,
                (
                    TASK_OUTPUT_HEADER_SIZE + len(teardown_output),
                    cairo_test_program_hash,
                ),
                teardown_output,
            ]
        )

        assert aggregator_output == expected_aggregator_output


class TestInit:
    @pytest.mark.parametrize(
        "zkpi_path",
        [Path("test_data/22188088.json")],
    )
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


class TestBody:
    @pytest.mark.parametrize(
        "zkpi_path",
        [Path("test_data/22188088.json")],
    )
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
        ) = cairo_run("test_body", verify_squashed_dicts=True, **body_input)

        assert initial_args_commitment_low
        assert initial_args_commitment_high
        assert post_exec_commitment_low
        assert post_exec_commitment_high


class TestTeardown:
    @pytest.mark.parametrize(
        "zkpi_path",
        [
            Path("test_data/22188088.json"),
        ],
    )
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

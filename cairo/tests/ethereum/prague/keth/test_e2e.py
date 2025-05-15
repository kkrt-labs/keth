from pathlib import Path

import pytest
from ethereum.exceptions import InvalidBlock
from ethereum.prague.fork import state_transition
from ethereum_types.numeric import U64

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
    def test_e2e(self, cairo_run, zkpi_path, program_input):
        [
            init_body_commitment_low,
            init_body_commitment_high,
            init_teardown_commitment_low,
            init_teardown_commitment_high,
        ] = cairo_run("test_init", verify_squashed_dicts=True, **program_input)

        transactions_len = len(program_input["block"].transactions)
        first_half_body_input = load_body_input(zkpi_path, 0, transactions_len // 2)
        [
            first_half_body_pre_exec_commitment_low,
            first_half_body_pre_exec_commitment_high,
            first_half_body_post_exec_commitment_low,
            first_half_body_post_exec_commitment_high,
            first_half_body_start_index,
            first_half_body_len,
        ] = cairo_run("test_body", verify_squashed_dicts=True, **first_half_body_input)

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
            second_half_body_start_index,
            second_half_body_len,
        ] = cairo_run("test_body", verify_squashed_dicts=True, **second_half_body_input)

        teardown_input = load_teardown_input(zkpi_path)
        [
            teardown_init_commitment_low,
            teardown_init_commitment_high,
            teardown_body_commitment_low,
            teardown_body_commitment_high,
        ] = cairo_run("test_teardown", verify_squashed_dicts=True, **teardown_input)

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
        assert first_half_body_start_index == 0
        assert first_half_body_len == transactions_len // 2

        # glue the second half of the body to the teardown
        assert second_half_body_post_exec_commitment_low == teardown_body_commitment_low
        assert (
            second_half_body_post_exec_commitment_high == teardown_body_commitment_high
        )

        assert second_half_body_start_index == transactions_len // 2
        assert second_half_body_len == transactions_len - transactions_len // 2

        # glue init to the teardown
        assert init_teardown_commitment_low == teardown_init_commitment_low
        assert init_teardown_commitment_high == teardown_init_commitment_high


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
            start_index,
            len_,
        ) = cairo_run("test_body", verify_squashed_dicts=True, **body_input)

        assert initial_args_commitment_low
        assert initial_args_commitment_high
        assert post_exec_commitment_low
        assert post_exec_commitment_high
        assert start_index == 0
        assert len_ == min(int(U64.MAX_VALUE), len(body_input["block_transactions"]))


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

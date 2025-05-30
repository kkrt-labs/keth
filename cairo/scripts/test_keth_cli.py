#!/usr/bin/env python3
"""
Comprehensive test suite for the Keth CLI (Refactored Version).

This includes both unit tests (fast) and CLI integration tests.
Run with: pytest test_keth_cli_refactored.py -v
Or for quick unit tests only: pytest test_keth_cli_refactored.py -m unit -v

Refactored to reduce code duplication and improve maintainability.
"""

import json
import shutil
import tempfile
from pathlib import Path
from typing import Any, Dict
from unittest.mock import patch

import pytest
from scripts.keth import (
    KethContext,
    Step,
    StepHandler,
    app,
    get_chain_id_from_zkpi,
    get_default_program,
    get_next_proving_run_id,
    get_proving_run_dir,
    get_zkpi_path,
    validate_block_number,
    validate_body_params,
)
from typer.testing import CliRunner

# Test data constants
TEST_ZKPI_FILE = "test_data/21688509.json"
TEST_BLOCK_NUMBER = 21688509
TEST_CHAIN_ID = 1


# ============================================================================
# FIXTURES AND TEST UTILITIES
# ============================================================================


@pytest.fixture
def cli_runner():
    """Provide a CLI runner for tests."""
    return CliRunner()


@pytest.fixture
def temp_data_dir():
    """Provide a temporary data directory with test ZKPI file."""
    with tempfile.TemporaryDirectory() as temp_dir:
        data_dir = Path(temp_dir) / "data"
        data_dir.mkdir(parents=True)

        # Set up test ZKPI file
        zkpi_dir = data_dir / str(TEST_CHAIN_ID) / str(TEST_BLOCK_NUMBER)
        zkpi_dir.mkdir(parents=True, exist_ok=True)
        zkpi_dest = zkpi_dir / "zkpi_1.json"
        shutil.copy2(TEST_ZKPI_FILE, zkpi_dest)

        yield data_dir


@pytest.fixture
def mock_compiled_program(tmp_path):
    """Create a mock compiled program file."""

    def _create_program(step: Step) -> Path:
        program_path = tmp_path / f"{step.value}_compiled.json"
        program_data = {
            "prime": "0x800000000000011000000000000000000000000000000000000000000000001",
            "data": [],
            "hints": {},
            "main_scope": "main",
            "identifiers": {},
            "reference_manager": {"references": []},
            "attributes": [],
        }

        with open(program_path, "w") as f:
            json.dump(program_data, f)

        return program_path

    return _create_program


class MockValidationHelper:
    """Helper for mocking typer validation functions."""

    @staticmethod
    def mock_typer_exit():
        """Context manager for mocking typer.Exit to raise RuntimeError instead."""
        return patch(
            "scripts.keth.typer.Exit",
            side_effect=RuntimeError("Validation failed"),
        )


class CLITestHelper:
    """Helper class for CLI testing patterns."""

    @staticmethod
    def create_mock_file(path: Path, data: Dict[str, Any]) -> Path:
        """Create a mock file with JSON data."""
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w") as f:
            json.dump(data, f)
        return path

    @staticmethod
    def assert_success_with_message(result, expected_message: str):
        """Assert CLI result is successful and contains expected message."""
        assert result.exit_code == 0
        assert expected_message in result.stdout

    @staticmethod
    def assert_error_with_message(result, expected_message: str):
        """Assert CLI result failed and contains expected error message."""
        assert result.exit_code == 1
        assert expected_message in result.stdout


# ============================================================================
# UNIT TESTS
# ============================================================================


@pytest.mark.unit
class TestKethUnits:
    """Unit tests for individual Keth functions."""

    def test_proving_run_id_generation(self, temp_data_dir):
        """Test that proving run IDs are generated correctly."""
        # First run should be 1
        run_id = get_next_proving_run_id(temp_data_dir, 1, 19426587)
        assert run_id == 1

        # Create directory for run 1
        run_dir = temp_data_dir / "1" / "19426587" / "1"
        run_dir.mkdir(parents=True)

        # Next run should be 2
        run_id = get_next_proving_run_id(temp_data_dir, 1, 19426587)
        assert run_id == 2

        # Create directory for run 3 (skipping 2)
        run_dir_3 = temp_data_dir / "1" / "19426587" / "3"
        run_dir_3.mkdir(parents=True)

        # Next run should be 4 (max + 1)
        run_id = get_next_proving_run_id(temp_data_dir, 1, 19426587)
        assert run_id == 4

    def test_path_generation(self):
        """Test path generation functions."""
        data_dir = Path("/test/data")

        # Test ZKPI path
        zkpi_path = get_zkpi_path(data_dir, 1, 19426587, "2")
        expected = data_dir / "1" / "19426587" / "zkpi_2.json"
        assert zkpi_path == expected

        # Test proving run directory
        run_dir = get_proving_run_dir(data_dir, 1, 19426587, 3)
        expected = data_dir / "1" / "19426587" / "3"
        assert run_dir == expected

    def test_chain_id_extraction(self):
        """Test chain ID extraction from real ZKPI file."""
        chain_id = get_chain_id_from_zkpi(Path(TEST_ZKPI_FILE))
        assert chain_id == TEST_CHAIN_ID

    def test_body_params_validation(self):
        """Test body step parameter validation."""
        with patch("scripts.keth.typer.echo"), MockValidationHelper.mock_typer_exit():

            # Valid body step
            validate_body_params(Step.BODY, 0, 10)  # Should not raise

            # Invalid cases should raise
            with pytest.raises(RuntimeError):
                validate_body_params(Step.BODY, None, 10)  # Missing start_index

            with pytest.raises(RuntimeError):
                validate_body_params(Step.BODY, 0, None)  # Missing chunk_size

            with pytest.raises(RuntimeError):
                validate_body_params(Step.BODY, -1, 10)  # Negative start_index

            with pytest.raises(RuntimeError):
                validate_body_params(Step.BODY, 0, 0)  # Zero chunk_size

            # Non-body step should not validate
            validate_body_params(Step.INIT, None, None)  # Should not raise

    def test_block_number_validation(self):
        """Test block number validation."""
        with patch("scripts.keth.typer.echo"), MockValidationHelper.mock_typer_exit():

            # Valid block number (after Cancun fork)
            validate_block_number(19426587)  # Should not raise

            # Invalid block number (before Cancun fork)
            with pytest.raises(RuntimeError):
                validate_block_number(19426586)

    def test_get_default_program(self):
        """Test default program path generation."""
        expected_programs = {
            Step.MAIN: "build/main_compiled.json",
            Step.INIT: "build/init_compiled.json",
            Step.BODY: "build/body_compiled.json",
            Step.TEARDOWN: "build/teardown_compiled.json",
            Step.AGGREGATOR: "build/aggregator_compiled.json",
        }

        for step, expected_path in expected_programs.items():
            assert get_default_program(step) == Path(expected_path)


@pytest.mark.unit
class TestKethContext:
    """Test the KethContext class."""

    def test_context_creation_with_chain_id(self, temp_data_dir):
        """Test KethContext creation with explicit chain ID."""
        ctx = KethContext.create(
            data_dir=temp_data_dir,
            block_number=TEST_BLOCK_NUMBER,
            chain_id=TEST_CHAIN_ID,
        )

        assert ctx.chain_id == TEST_CHAIN_ID
        assert ctx.block_number == TEST_BLOCK_NUMBER
        assert ctx.proving_run_id == 1
        assert ctx.zkpi_path.exists()
        assert ctx.proving_run_dir.exists()

    def test_context_creation_auto_detect_chain_id(self, temp_data_dir):
        """Test KethContext creation with auto-detected chain ID."""
        ctx = KethContext.create(
            data_dir=temp_data_dir,
            block_number=TEST_BLOCK_NUMBER,
        )

        assert ctx.chain_id == TEST_CHAIN_ID
        assert ctx.block_number == TEST_BLOCK_NUMBER


@pytest.mark.unit
class TestStepHandler:
    """Test the StepHandler class."""

    def test_output_filename_generation(self):
        """Test output filename generation for different steps."""
        # Regular step
        filename = StepHandler.get_output_filename(Step.MAIN, 12345)
        assert filename == "prover_input_info_12345.json"

        # Init step
        filename = StepHandler.get_output_filename(Step.INIT, 12345)
        assert filename == "prover_input_info_12345_init.json"

        # Teardown step
        filename = StepHandler.get_output_filename(Step.TEARDOWN, 12345)
        assert filename == "prover_input_info_12345_teardown.json"

        # Aggregator step
        filename = StepHandler.get_output_filename(Step.AGGREGATOR, 12345)
        assert filename == "prover_input_info_12345_aggregator.json"

        # Body step with indices
        filename = StepHandler.get_output_filename(Step.BODY, 12345, 0, 5)
        assert filename == "prover_input_info_12345_body_0_5.json"

    def test_proof_filename_generation(self):
        """Test proof filename generation for different steps."""
        test_cases = [
            (Step.MAIN, None, None, "proof.json"),
            (Step.INIT, None, None, "proof_init.json"),
            (Step.TEARDOWN, None, None, "proof_teardown.json"),
            (Step.BODY, 0, 5, "proof_body_0_5.json"),
            (Step.AGGREGATOR, None, None, "proof_aggregator.json"),
        ]

        for step, start_index, chunk_size, expected in test_cases:
            filename = StepHandler.get_proof_filename(step, start_index, chunk_size)
            assert filename == expected


# ============================================================================
# CLI INTEGRATION TESTS
# ============================================================================


@pytest.mark.integration
class TestKethCLIBase:
    """Base class for CLI tests with common functionality."""

    def setup_method(self):
        """Set up test fixtures before each test."""
        self.runner = CliRunner()
        self.helper = CLITestHelper()


@pytest.mark.integration
class TestTraceCommand(TestKethCLIBase):
    """Test suite for the trace command."""

    def test_trace_command_auto_detect_chain_id(
        self, temp_data_dir, mock_compiled_program
    ):
        """Test that trace command can auto-detect chain ID from ZKPI file."""
        program_path = mock_compiled_program(Step.MAIN)

        with patch("scripts.keth.run_generate_trace") as mock_trace:
            result = self.runner.invoke(
                app,
                [
                    "trace",
                    "-b",
                    str(TEST_BLOCK_NUMBER),
                    "--data-dir",
                    str(temp_data_dir),
                    "--compiled-program",
                    str(program_path),
                ],
            )

        self.helper.assert_success_with_message(result, "Trace generated successfully")
        mock_trace.assert_called_once()

    def test_trace_command_missing_zkpi_file(self, temp_data_dir):
        """Test error handling when ZKPI file is missing."""
        result = self.runner.invoke(
            app,
            [
                "trace",
                "-b",
                "99999999",  # Non-existent block
                "--data-dir",
                str(temp_data_dir),
            ],
        )

        self.helper.assert_error_with_message(result, "ZKPI file not found")

    def test_trace_command_body_step_validation(self, temp_data_dir):
        """Test that body step requires start-index and len parameters."""
        result = self.runner.invoke(
            app,
            [
                "trace",
                "-b",
                str(TEST_BLOCK_NUMBER),
                "-s",
                "body",
                "--data-dir",
                str(temp_data_dir),
            ],
        )

        self.helper.assert_error_with_message(
            result, "start-index and --len parameters are required"
        )

    def test_trace_command_body_step_with_params(
        self, temp_data_dir, mock_compiled_program
    ):
        """Test body step with valid parameters."""
        program_path = mock_compiled_program(Step.BODY)

        with patch("scripts.keth.run_generate_trace") as mock_trace:
            result = self.runner.invoke(
                app,
                [
                    "trace",
                    "-b",
                    str(TEST_BLOCK_NUMBER),
                    "-s",
                    "body",
                    "--start-index",
                    "0",
                    "--len",
                    "1",
                    "--data-dir",
                    str(temp_data_dir),
                    "--compiled-program",
                    str(program_path),
                ],
            )

        self.helper.assert_success_with_message(result, "Trace generated successfully")
        mock_trace.assert_called_once()

    def test_trace_command_with_explicit_chain_id(
        self, temp_data_dir, mock_compiled_program
    ):
        """Test trace command with explicitly provided chain ID."""
        program_path = mock_compiled_program(Step.MAIN)

        with patch("scripts.keth.run_generate_trace") as mock_trace:
            result = self.runner.invoke(
                app,
                [
                    "trace",
                    "-b",
                    str(TEST_BLOCK_NUMBER),
                    "--chain-id",
                    str(TEST_CHAIN_ID),
                    "--data-dir",
                    str(temp_data_dir),
                    "--compiled-program",
                    str(program_path),
                ],
            )

        self.helper.assert_success_with_message(result, "Trace generated successfully")
        mock_trace.assert_called_once()

    def test_trace_command_invalid_block_number(self, temp_data_dir):
        """Test trace command with invalid block number (before Cancun fork)."""
        result = self.runner.invoke(
            app,
            [
                "trace",
                "-b",
                "19426586",  # Before Cancun fork
                "--data-dir",
                str(temp_data_dir),
            ],
        )

        self.helper.assert_error_with_message(result, "before Cancun fork")


@pytest.mark.integration
class TestProveCommand(TestKethCLIBase):
    """Test suite for the prove command."""

    def test_prove_command(self, temp_data_dir):
        """Test the prove command."""
        # Create a mock prover inputs file
        prover_inputs_path = (
            temp_data_dir / f"prover_input_info_{TEST_BLOCK_NUMBER}.json"
        )
        self.helper.create_mock_file(prover_inputs_path, {"test": "data"})

        with patch("scripts.keth.run_prove") as mock_prove:
            result = self.runner.invoke(
                app,
                [
                    "prove",
                    "--prover-inputs-path",
                    str(prover_inputs_path),
                    "--data-dir",
                    str(temp_data_dir),
                ],
            )

        self.helper.assert_success_with_message(result, "Proof generated successfully")
        mock_prove.assert_called_once()


@pytest.mark.integration
class TestVerifyCommand(TestKethCLIBase):
    """Test suite for the verify command."""

    def test_verify_command(self, tmp_path):
        """Test the verify command."""
        # Create a mock proof file
        proof_path = tmp_path / "proof.json"
        self.helper.create_mock_file(proof_path, {"test": "proof"})

        with patch("scripts.keth.run_verify") as mock_verify:
            result = self.runner.invoke(
                app, ["verify", "--proof-path", str(proof_path)]
            )

        self.helper.assert_success_with_message(result, "Proof verified successfully")
        mock_verify.assert_called_once()


@pytest.mark.integration
class TestE2ECommand(TestKethCLIBase):
    """Test suite for the e2e command."""

    def test_e2e_command_main_step(self, temp_data_dir, mock_compiled_program):
        """Test e2e command with main step."""
        program_path = mock_compiled_program(Step.MAIN)

        with patch("scripts.keth.run_end_to_end") as mock_e2e:
            result = self.runner.invoke(
                app,
                [
                    "e2e",
                    "-b",
                    str(TEST_BLOCK_NUMBER),
                    "-s",
                    "main",
                    "--data-dir",
                    str(temp_data_dir),
                    "--compiled-program",
                    str(program_path),
                ],
            )

        self.helper.assert_success_with_message(
            result, "Pipeline completed successfully"
        )
        mock_e2e.assert_called_once()

        # Check that the proof path is correct
        call_args = mock_e2e.call_args
        proof_path = Path(call_args[0][3])  # positional argument
        assert proof_path.name == "proof.json"

    def test_e2e_command_body_step_filename(self, temp_data_dir, mock_compiled_program):
        """Test that body step generates correct filename with indices."""
        program_path = mock_compiled_program(Step.BODY)

        with patch("scripts.keth.run_end_to_end") as mock_e2e:
            result = self.runner.invoke(
                app,
                [
                    "e2e",
                    "-b",
                    str(TEST_BLOCK_NUMBER),
                    "-s",
                    "body",
                    "--start-index",
                    "0",
                    "--len",
                    "1",
                    "--data-dir",
                    str(temp_data_dir),
                    "--compiled-program",
                    str(program_path),
                ],
            )

        self.helper.assert_success_with_message(
            result, "Pipeline completed successfully"
        )
        call_args = mock_e2e.call_args
        proof_path = Path(call_args[0][3])  # positional argument
        assert proof_path.name == "proof_body_0_1.json"


@pytest.mark.integration
class TestHelpCommands(TestKethCLIBase):
    """Test help functionality."""

    @pytest.mark.parametrize("command", ["trace", "prove", "verify", "e2e"])
    def test_help_commands(self, command):
        """Test that help commands work correctly."""
        result = self.runner.invoke(app, [command, "--help"])
        assert result.exit_code == 0
        assert "Usage:" in result.stdout


# ============================================================================
# WORKFLOW TESTS (End-to-end scenarios)
# ============================================================================


@pytest.mark.integration
class TestKethWorkflows(TestKethCLIBase):
    """Integration tests that test multiple commands together."""

    def test_trace_then_prove_workflow(self, temp_data_dir, mock_compiled_program):
        """Test the complete trace -> prove workflow."""
        program_path = mock_compiled_program(Step.MAIN)

        # Step 1: Generate trace
        with patch("scripts.keth.run_generate_trace"):
            trace_result = self.runner.invoke(
                app,
                [
                    "trace",
                    "-b",
                    str(TEST_BLOCK_NUMBER),
                    "--data-dir",
                    str(temp_data_dir),
                    "--compiled-program",
                    str(program_path),
                ],
            )

        self.helper.assert_success_with_message(
            trace_result, "Trace generated successfully"
        )

        # Step 2: Generate proof (mock the prover inputs file)
        prover_inputs_path = (
            temp_data_dir / f"prover_input_info_{TEST_BLOCK_NUMBER}.json"
        )
        prover_inputs_path.touch()  # Create empty file

        with patch("scripts.keth.run_prove"):
            prove_result = self.runner.invoke(
                app,
                [
                    "prove",
                    "--prover-inputs-path",
                    str(prover_inputs_path),
                    "--data-dir",
                    str(temp_data_dir),
                ],
            )

        self.helper.assert_success_with_message(
            prove_result, "Proof generated successfully"
        )

    def test_full_e2e_workflow(self, temp_data_dir, mock_compiled_program):
        """Test the complete e2e workflow with verification."""
        program_path = mock_compiled_program(Step.MAIN)

        with patch("scripts.keth.run_end_to_end") as mock_e2e:
            result = self.runner.invoke(
                app,
                [
                    "e2e",
                    "-b",
                    str(TEST_BLOCK_NUMBER),
                    "--verify",
                    "--data-dir",
                    str(temp_data_dir),
                    "--compiled-program",
                    str(program_path),
                ],
            )

        self.helper.assert_success_with_message(
            result, "Pipeline completed successfully"
        )
        mock_e2e.assert_called_once()
        # Verify that verification was enabled
        call_args = mock_e2e.call_args
        assert call_args[0][5]  # verify_proof parameter


# ============================================================================
# PROPERTY-BASED TESTS (Optional, requires hypothesis)
# ============================================================================

try:
    from hypothesis import given
    from hypothesis import strategies as st

    @pytest.mark.unit
    class TestKethProperties:
        """Property-based tests for CLI behavior."""

        @given(
            chain_id=st.integers(min_value=1, max_value=1000),
            block_number=st.integers(min_value=1, max_value=1000000),
            version=st.text(
                min_size=1,
                max_size=10,
                alphabet=st.characters(whitelist_categories=("Nd", "Lu", "Ll")),
            ),
        )
        def test_path_generation_properties(self, chain_id, block_number, version):
            """Test that path generation is consistent and valid."""
            data_dir = Path("/tmp/test")

            # Test ZKPI path generation
            zkpi_path = get_zkpi_path(data_dir, chain_id, block_number, version)
            assert str(chain_id) in str(zkpi_path)
            assert str(block_number) in str(zkpi_path)
            assert version in str(zkpi_path)

            # Test proving run directory generation
            proving_run_dir = get_proving_run_dir(data_dir, chain_id, block_number, 1)
            assert str(chain_id) in str(proving_run_dir)
            assert str(block_number) in str(proving_run_dir)
            assert "1" in str(proving_run_dir)

except ImportError:
    # Hypothesis not available, skip property-based tests
    pass


@pytest.mark.integration
class TestGenerateArPiesCommand(TestKethCLIBase):
    """Test suite for the generate_ar_pies command."""

    def test_generate_ar_pies_command_basic(self, temp_data_dir, mock_compiled_program):
        """Test basic generate_ar_pies functionality."""
        # Create mock compiled programs for all required steps
        mock_compiled_program(Step.INIT)
        mock_compiled_program(Step.BODY)
        mock_compiled_program(Step.TEARDOWN)

        with patch("scripts.keth.run_generate_trace") as mock_trace:
            result = self.runner.invoke(
                app,
                [
                    "generate-ar-pies",
                    "-b",
                    str(TEST_BLOCK_NUMBER),
                    "--data-dir",
                    str(temp_data_dir),
                    "--body-chunk-size",
                    "5",
                ],
            )

        self.helper.assert_success_with_message(
            result, "All AR-PIE traces generated successfully"
        )
        # Should call generate_trace multiple times (init + body chunks + teardown)
        assert mock_trace.call_count >= 3

    def test_generate_ar_pies_command_with_options(
        self, temp_data_dir, mock_compiled_program
    ):
        """Test generate_ar_pies with various options."""
        # Create mock compiled programs
        mock_compiled_program(Step.INIT)
        mock_compiled_program(Step.BODY)
        mock_compiled_program(Step.TEARDOWN)

        with patch("scripts.keth.run_generate_trace") as mock_trace:
            result = self.runner.invoke(
                app,
                [
                    "generate-ar-pies",
                    "-b",
                    str(TEST_BLOCK_NUMBER),
                    "--data-dir",
                    str(temp_data_dir),
                    "--body-chunk-size",
                    "3",
                    "--output-trace-components",
                    "--pi-json",
                    "--proving-run-id",
                    "42",
                ],
            )

        self.helper.assert_success_with_message(
            result, "All AR-PIE traces generated successfully"
        )
        # Verify options are passed to the trace generation function
        for call in mock_trace.call_args_list:
            args, kwargs = call
            assert kwargs["output_trace_components"] is True
            assert kwargs["pi_json"] is True

    def test_generate_ar_pies_command_body_chunking(
        self, temp_data_dir, mock_compiled_program
    ):
        """Test that body steps are properly chunked."""
        # Create mock compiled programs
        mock_compiled_program(Step.INIT)
        mock_compiled_program(Step.BODY)
        mock_compiled_program(Step.TEARDOWN)

        with patch("scripts.keth.run_generate_trace"):
            result = self.runner.invoke(
                app,
                [
                    "generate-ar-pies",
                    "-b",
                    str(TEST_BLOCK_NUMBER),
                    "--data-dir",
                    str(temp_data_dir),
                    "--body-chunk-size",
                    "2",  # Small chunk size to force multiple chunks
                ],
            )

        self.helper.assert_success_with_message(
            result, "All AR-PIE traces generated successfully"
        )

        # Check that body chunks appear in the output with correct ranges
        # With 8 transactions and chunk size 2, we should have body chunks [0:2], [2:4], [4:6], [6:8]
        assert "body [0:2]" in result.stdout
        assert "body [2:4]" in result.stdout
        assert "body [4:6]" in result.stdout
        assert "body [6:8]" in result.stdout

    def test_generate_ar_pies_invalid_block_number(self, temp_data_dir):
        """Test generate_ar_pies with invalid block number."""
        result = self.runner.invoke(
            app,
            [
                "generate-ar-pies",
                "-b",
                "19426586",  # Before Cancun fork
                "--data-dir",
                str(temp_data_dir),
            ],
        )

        self.helper.assert_error_with_message(result, "before Cancun fork")

    def test_generate_ar_pies_filename_consistency(
        self, temp_data_dir, mock_compiled_program
    ):
        """Test that generated filenames match the expected naming pattern."""
        # Create mock compiled programs
        mock_compiled_program(Step.INIT)
        mock_compiled_program(Step.BODY)
        mock_compiled_program(Step.TEARDOWN)

        with patch("scripts.keth.run_generate_trace") as mock_trace:
            result = self.runner.invoke(
                app,
                [
                    "generate-ar-pies",
                    "-b",
                    str(TEST_BLOCK_NUMBER),
                    "--data-dir",
                    str(temp_data_dir),
                    "--body-chunk-size",
                    "10",
                ],
            )

        self.helper.assert_success_with_message(
            result, "All AR-PIE traces generated successfully"
        )

        # Check that the output files use the correct naming pattern
        for call in mock_trace.call_args_list:
            args, kwargs = call
            output_path = Path(kwargs["output_path"])
            filename = output_path.name

            # Should match the expected patterns
            assert (
                filename.endswith("_init.json")
                or filename.endswith("_teardown.json")
                or "_body_" in filename
            ), f"Unexpected filename pattern: {filename}"

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
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Dict
from unittest.mock import patch

import pytest
from scripts.keth import (
    PRAGUE_FORK_BLOCK,
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
TEST_ZKPI_FILE = "test_data/22615247.json"
TEST_BLOCK_NUMBER = PRAGUE_FORK_BLOCK
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
        zkpi_dest = zkpi_dir / "zkpi.json"
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


@pytest.fixture
def mock_all_programs(mock_compiled_program):
    """Create mock programs for all steps and provide a patched get_default_program."""
    # Create all required programs
    programs = {
        Step.INIT: mock_compiled_program(Step.INIT),
        Step.BODY: mock_compiled_program(Step.BODY),
        Step.TEARDOWN: mock_compiled_program(Step.TEARDOWN),
        Step.AGGREGATOR: mock_compiled_program(Step.AGGREGATOR),
        Step.MAIN: mock_compiled_program(Step.MAIN),
    }

    def mock_get_default_program(step: Step) -> Path:
        return programs[step]

    @contextmanager
    def patch_get_default_program():
        with patch(
            "scripts.keth.get_default_program", side_effect=mock_get_default_program
        ):
            yield programs

    return programs, patch_get_default_program


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
        assert result.exit_code == 0, f"CLI result: {result.stdout}"
        assert expected_message in result.stdout

    @staticmethod
    def assert_error_with_message(result, expected_message: str):
        """Assert CLI result failed and contains expected error message."""
        assert result.exit_code == 1
        assert expected_message in result.stdout


@pytest.fixture
def mock_generate_ar_setup(mock_all_programs):
    """Setup fixture for generate_ar_inputs tests with all necessary mocks."""
    programs, patch_get_default_program = mock_all_programs

    def mock_load_program_input_for_aggregator(
        step, zkpi_path, start_index=None, chunk_size=None
    ):
        """Mock load_program_input that handles the aggregator step properly."""
        if step == Step.AGGREGATOR:
            # Return mock aggregator input
            return {
                "keth_segment_outputs": [[1, 2, 3], [4, 5, 6], [7, 8, 9]],
                "keth_segment_program_hashes": {
                    "init": 12345,
                    "body": 67890,
                    "teardown": 11111,
                },
                "n_body_chunks": 2,
            }
        else:
            # For other steps, use the original implementation
            from scripts.keth import (
                load_body_input,
                load_teardown_input,
                load_zkpi_fixture,
            )

            match step:
                case Step.BODY:
                    return load_body_input(zkpi_path, start_index, chunk_size)
                case Step.TEARDOWN:
                    return load_teardown_input(zkpi_path)
                case _:
                    return load_zkpi_fixture(zkpi_path)

    from contextlib import contextmanager

    @contextmanager
    def patch_all_for_generate_ar():
        with (
            patch_get_default_program(),
            patch(
                "scripts.keth.StepHandler.load_program_input",
                side_effect=mock_load_program_input_for_aggregator,
            ),
        ):
            yield programs

    return programs, patch_all_for_generate_ar


# ============================================================================
# UNIT TESTS
# ============================================================================


@pytest.mark.unit
class TestKethUnits:
    """Unit tests for individual Keth functions."""

    def test_proving_run_id_generation(self, temp_data_dir):
        """Test that proving run IDs are generated correctly."""
        # First run should be "1"
        run_id = get_next_proving_run_id(temp_data_dir, 1, 19426587)
        assert run_id == "1"

        # Create directory for run 1
        run_dir = temp_data_dir / "1" / "19426587" / "1"
        run_dir.mkdir(parents=True)

        # Next run should be "2"
        run_id = get_next_proving_run_id(temp_data_dir, 1, 19426587)
        assert run_id == "2"

        # Create directory for run 3 (skipping 2)
        run_dir_3 = temp_data_dir / "1" / "19426587" / "3"
        run_dir_3.mkdir(parents=True)

        # Next run should be "4" (max + 1)
        run_id = get_next_proving_run_id(temp_data_dir, 1, 19426587)
        assert run_id == "4"

    def test_path_generation(self):
        """Test path generation functions."""
        data_dir = Path("/test/data")

        # Test ZKPI path
        zkpi_path = get_zkpi_path(data_dir, 1, 19426587, "2")
        expected = data_dir / "1" / "19426587" / "zkpi.json"
        assert zkpi_path == expected

        # Test proving run directory
        run_dir = get_proving_run_dir(data_dir, 1, 19426587, "3")
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

            # Valid block number (after Prague fork)
            validate_block_number(PRAGUE_FORK_BLOCK)  # Should not raise

            # Invalid block number (before Prague fork)
            with pytest.raises(RuntimeError):
                validate_block_number(PRAGUE_FORK_BLOCK - 1)

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
        assert ctx.proving_run_id == "1"
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
        assert filename == "prover_input_info_12345"

        # Init step
        filename = StepHandler.get_output_filename(Step.INIT, 12345)
        assert filename == "prover_input_info_12345_init"

        # Teardown step
        filename = StepHandler.get_output_filename(Step.TEARDOWN, 12345)
        assert filename == "prover_input_info_12345_teardown"

        # Aggregator step
        filename = StepHandler.get_output_filename(Step.AGGREGATOR, 12345)
        assert filename == "prover_input_info_12345_aggregator"

        # Body step with indices
        filename = StepHandler.get_output_filename(Step.BODY, 12345, 0, 5)
        assert filename == "prover_input_info_12345_body_0_5"

        # Cairo PIE files
        filename = StepHandler.get_output_filename(Step.INIT, 12345, cairo_pie=True)
        assert filename == "cairo_pie_12345_init.zip"

        filename = StepHandler.get_output_filename(
            Step.BODY, 12345, 0, 5, cairo_pie=True
        )
        assert filename == "cairo_pie_12345_body_0_5.zip"

        filename = StepHandler.get_output_filename(Step.TEARDOWN, 12345, cairo_pie=True)
        assert filename == "cairo_pie_12345_teardown.zip"

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

    def test_trace_command_auto_detect_chain_id(self, temp_data_dir, mock_all_programs):
        """Test that trace command can auto-detect chain ID from ZKPI file."""
        programs, patch_get_default_program = mock_all_programs
        with patch("scripts.keth.run_generate_trace") as mock_trace:
            result = self.runner.invoke(
                app,
                [
                    "trace",
                    "-b",
                    str(TEST_BLOCK_NUMBER),
                    "--data-dir",
                    str(temp_data_dir),
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
        self, temp_data_dir, mock_all_programs
    ):
        """Test body step with valid parameters."""
        programs, patch_get_default_program = mock_all_programs
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
                ],
            )

        self.helper.assert_success_with_message(result, "Trace generated successfully")
        mock_trace.assert_called_once()

    def test_trace_command_with_explicit_chain_id(
        self, temp_data_dir, mock_all_programs
    ):
        """Test trace command with explicitly provided chain ID."""
        programs, patch_get_default_program = mock_all_programs
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
                ],
            )

        self.helper.assert_success_with_message(result, "Trace generated successfully")
        mock_trace.assert_called_once()

    def test_trace_command_invalid_block_number(self, temp_data_dir):
        """Test trace command with invalid block number (before Prague fork)."""
        result = self.runner.invoke(
            app,
            [
                "trace",
                "-b",
                str(PRAGUE_FORK_BLOCK - 1),  # Before Prague fork
                "--data-dir",
                str(temp_data_dir),
            ],
        )

        self.helper.assert_error_with_message(result, "before Prague fork")

    def test_trace_command_with_cairo_pie(self, temp_data_dir, mock_all_programs):
        """Test trace command with Cairo PIE output."""
        programs, patch_get_default_program = mock_all_programs
        with patch("scripts.keth.run_generate_trace") as mock_trace:
            result = self.runner.invoke(
                app,
                [
                    "trace",
                    "-b",
                    str(TEST_BLOCK_NUMBER),
                    "--data-dir",
                    str(temp_data_dir),
                    "--cairo-pie",
                ],
            )

        self.helper.assert_success_with_message(result, "Trace generated successfully")
        mock_trace.assert_called_once()

        # Verify cairo_pie parameter was passed correctly
        call_args = mock_trace.call_args
        assert call_args[1]["cairo_pie"] is True

    def test_trace_command_generates_run_output_file(
        self, temp_data_dir, mock_all_programs
    ):
        """Test that trace command generates run_output.txt file."""
        programs, patch_get_default_program = mock_all_programs

        # Mock the actual file system writes to simulate the Rust function behavior
        written_files = []
        original_write = open

        def mock_write_side_effect(*args, **kwargs):
            # Capture write operations to track run_output.txt creation
            if (
                len(args) >= 2
                and isinstance(args[0], (str, Path))
                and "run_output" in str(args[0])
            ):
                written_files.append(str(args[0]))
            return original_write(*args, **kwargs)

        with (
            patch("scripts.keth.run_generate_trace") as mock_trace,
            patch("builtins.open", side_effect=mock_write_side_effect),
            patch("pathlib.Path.write_text"),
            patch_get_default_program(),
        ):
            # Configure the mock to simulate run_output.txt creation
            def trace_side_effect(*args, **kwargs):
                output_path = kwargs.get("output_path")
                if output_path:
                    # Simulate the run_output.txt file creation that happens in Rust
                    run_output_path = Path(str(output_path)).with_name(
                        f"{Path(str(output_path)).stem}.run_output.txt"
                    )
                    written_files.append(str(run_output_path))

            mock_trace.side_effect = trace_side_effect

            result = self.runner.invoke(
                app,
                [
                    "trace",
                    "-b",
                    str(TEST_BLOCK_NUMBER),
                    "--data-dir",
                    str(temp_data_dir),
                ],
            )

        self.helper.assert_success_with_message(result, "Trace generated successfully")
        mock_trace.assert_called_once()

        # Verify run_output.txt file creation was simulated
        run_output_files = [f for f in written_files if "run_output.txt" in f]
        assert (
            len(run_output_files) > 0
        ), f"Expected run_output.txt file to be created, but found: {written_files}"


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

    def test_e2e_command_main_step(self, temp_data_dir, mock_all_programs):
        """Test e2e command with main step."""
        programs, patch_get_default_program = mock_all_programs
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

    def test_e2e_command_body_step_filename(self, temp_data_dir, mock_all_programs):
        """Test that body step generates correct filename with indices."""
        programs, patch_get_default_program = mock_all_programs
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
                ],
            )

        self.helper.assert_success_with_message(
            result, "Pipeline completed successfully"
        )
        call_args = mock_e2e.call_args
        proof_path = Path(call_args[0][3])  # positional argument
        assert proof_path.name == "proof_body_0_1.json"

    def test_e2e_command_generates_run_output_file(
        self, temp_data_dir, mock_all_programs
    ):
        """Test that e2e command generates run_output.txt file."""
        programs, patch_get_default_program = mock_all_programs

        # Mock the actual file system writes to simulate the Rust function behavior
        written_files = []

        def mock_e2e_side_effect(*args, **kwargs):
            # Simulate the run_output.txt file creation that happens in run_end_to_end
            proof_path = Path(args[3])  # proof_path is 4th positional argument
            run_output_path = proof_path.with_name("run_output.txt")
            written_files.append(str(run_output_path))

        with (
            patch(
                "scripts.keth.run_end_to_end", side_effect=mock_e2e_side_effect
            ) as mock_e2e,
            patch_get_default_program(),
        ):
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
                ],
            )

        self.helper.assert_success_with_message(
            result, "Pipeline completed successfully"
        )
        mock_e2e.assert_called_once()

        # Verify run_output.txt file creation was simulated
        run_output_files = [f for f in written_files if "run_output.txt" in f]
        assert (
            len(run_output_files) == 1
        ), f"Expected exactly one run_output.txt file to be created, but found: {written_files}"
        assert "run_output.txt" in run_output_files[0]

    def test_e2e_command_with_verification_generates_run_output_file(
        self, temp_data_dir, mock_all_programs
    ):
        """Test that e2e command with verification still generates run_output.txt file."""
        programs, patch_get_default_program = mock_all_programs

        # Mock the actual file system writes to simulate the Rust function behavior
        written_files = []

        def mock_e2e_side_effect(*args, **kwargs):
            # Simulate the run_output.txt file creation that happens in run_end_to_end
            proof_path = Path(args[3])  # proof_path is 4th positional argument
            run_output_path = proof_path.with_name("run_output.txt")
            written_files.append(str(run_output_path))

        with (
            patch(
                "scripts.keth.run_end_to_end", side_effect=mock_e2e_side_effect
            ) as mock_e2e,
            patch_get_default_program(),
        ):
            result = self.runner.invoke(
                app,
                [
                    "e2e",
                    "-b",
                    str(TEST_BLOCK_NUMBER),
                    "-s",
                    "main",
                    "--verify",
                    "--data-dir",
                    str(temp_data_dir),
                ],
            )

        self.helper.assert_success_with_message(
            result, "Pipeline completed successfully"
        )
        mock_e2e.assert_called_once()

        # Verify run_output.txt file creation was simulated
        run_output_files = [f for f in written_files if "run_output.txt" in f]
        assert (
            len(run_output_files) == 1
        ), f"Expected exactly one run_output.txt file to be created, but found: {written_files}"
        assert "run_output.txt" in run_output_files[0]

        # Verify that verification was enabled
        call_args = mock_e2e.call_args
        assert call_args[0][5]  # verify_proof parameter

    def test_e2e_command_run_output_file_path_generation(
        self, temp_data_dir, mock_all_programs
    ):
        """Test that e2e command generates run_output.txt with correct path relative to proof path."""
        programs, patch_get_default_program = mock_all_programs

        written_files = []
        proof_paths = []

        def mock_e2e_side_effect(*args, **kwargs):
            proof_path = Path(args[3])  # proof_path is 4th positional argument
            proof_paths.append(str(proof_path))
            run_output_path = proof_path.with_name("run_output.txt")
            written_files.append(str(run_output_path))

        with (
            patch("scripts.keth.run_end_to_end", side_effect=mock_e2e_side_effect),
            patch_get_default_program(),
        ):
            # Test body step to ensure filename is generated correctly
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
                    "5",
                    "--data-dir",
                    str(temp_data_dir),
                ],
            )

        self.helper.assert_success_with_message(
            result, "Pipeline completed successfully"
        )

        # Verify that the proof path and run_output path are correctly related
        assert len(proof_paths) == 1
        assert len(written_files) == 1

        proof_path = Path(proof_paths[0])
        run_output_path = Path(written_files[0])

        # The run_output.txt should be in the same directory as the proof file
        assert proof_path.parent == run_output_path.parent
        assert run_output_path.name == "run_output.txt"
        assert proof_path.name == "proof_body_0_5.json"


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

    def test_trace_then_prove_workflow(self, temp_data_dir, mock_all_programs):
        """Test the complete trace -> prove workflow."""
        programs, patch_get_default_program = mock_all_programs
        with patch("scripts.keth.run_generate_trace"):
            trace_result = self.runner.invoke(
                app,
                [
                    "trace",
                    "-b",
                    str(TEST_BLOCK_NUMBER),
                    "--data-dir",
                    str(temp_data_dir),
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

    def test_full_e2e_workflow(self, temp_data_dir, mock_all_programs):
        """Test the complete e2e workflow with verification."""
        programs, patch_get_default_program = mock_all_programs
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

            # Test proving run directory generation
            proving_run_dir = get_proving_run_dir(
                data_dir, chain_id, block_number, "proving-id-number"
            )
            assert str(chain_id) in str(proving_run_dir)
            assert str(block_number) in str(proving_run_dir)
            assert "proving-id-number" in str(proving_run_dir)

except ImportError:
    # Hypothesis not available, skip property-based tests
    pass


@pytest.mark.integration
class TestGenerateArPiesCommand(TestKethCLIBase):
    """Test suite for the generate_ar_inputs command."""

    def test_generate_ar_inputs_command_basic(
        self, temp_data_dir, mock_generate_ar_setup
    ):
        """Test basic generate_ar_inputs functionality."""
        programs, patch_all_for_generate_ar = mock_generate_ar_setup

        with (
            patch("scripts.keth.run_generate_trace") as mock_trace,
            patch_all_for_generate_ar(),
        ):
            result = self.runner.invoke(
                app,
                [
                    "generate-ar-inputs",
                    "-b",
                    str(TEST_BLOCK_NUMBER),
                    "--data-dir",
                    str(temp_data_dir),
                    "--body-chunk-size",
                    "5",
                ],
            )

        # Debug output if test fails
        if result.exit_code != 0:
            print(f"CLI exit code: {result.exit_code}")
            print(f"CLI stdout: {result.stdout}")
            print(f"CLI stderr: {result.stderr}")
            print(f"CLI exception: {result.exception}")

        self.helper.assert_success_with_message(
            result, "All AR inputs generated successfully"
        )
        # Should call generate_trace multiple times (init + body chunks + teardown + aggregator)
        assert mock_trace.call_count >= 3

    def test_generate_ar_inputs_command_with_options(
        self, temp_data_dir, mock_generate_ar_setup
    ):
        """Test generate_ar_inputs with various options."""
        programs, patch_all_for_generate_ar = mock_generate_ar_setup

        with (
            patch("scripts.keth.run_generate_trace") as mock_trace,
            patch_all_for_generate_ar(),
        ):
            result = self.runner.invoke(
                app,
                [
                    "generate-ar-inputs",
                    "-b",
                    str(TEST_BLOCK_NUMBER),
                    "--data-dir",
                    str(temp_data_dir),
                    "--body-chunk-size",
                    "3",
                    "--output-trace-components",
                    "--proving-run-id",
                    "42",
                ],
            )

        self.helper.assert_success_with_message(
            result, "All AR inputs generated successfully"
        )
        # Verify options are passed to the trace generation function
        for call in mock_trace.call_args_list:
            args, kwargs = call
            assert kwargs["output_trace_components"] is True

    def test_generate_ar_inputs_command_body_chunking(
        self, temp_data_dir, mock_generate_ar_setup
    ):
        """Test that body steps are properly chunked."""
        programs, patch_all_for_generate_ar = mock_generate_ar_setup

        with patch("scripts.keth.run_generate_trace"), patch_all_for_generate_ar():
            result = self.runner.invoke(
                app,
                [
                    "generate-ar-inputs",
                    "-b",
                    str(TEST_BLOCK_NUMBER),
                    "--data-dir",
                    str(temp_data_dir),
                    "--body-chunk-size",
                    "2",  # Small chunk size to force multiple chunks
                ],
            )

        self.helper.assert_success_with_message(
            result, "All AR inputs generated successfully"
        )

        # Check that body chunks appear in the output with correct ranges
        # With 8 transactions and chunk size 2, we should have body chunks [0:2], [2:4], [4:6], [6:8]
        assert "body [0:2]" in result.stdout
        assert "body [2:4]" in result.stdout
        assert "body [4:6]" in result.stdout
        assert "body [6:8]" in result.stdout

    def test_generate_ar_inputs_invalid_block_number(self, temp_data_dir):
        """Test generate_ar_inputs with invalid block number."""
        result = self.runner.invoke(
            app,
            [
                "generate-ar-inputs",
                "-b",
                str(PRAGUE_FORK_BLOCK - 1),  # Before Prague fork
                "--data-dir",
                str(temp_data_dir),
            ],
        )

        self.helper.assert_error_with_message(result, "before Prague fork")

    def test_generate_ar_inputs_filename_consistency(
        self, temp_data_dir, mock_generate_ar_setup
    ):
        """Test that generated filenames match the expected naming pattern."""
        programs, patch_all_for_generate_ar = mock_generate_ar_setup

        with (
            patch("scripts.keth.run_generate_trace") as mock_trace,
            patch_all_for_generate_ar(),
        ):
            result = self.runner.invoke(
                app,
                [
                    "generate-ar-inputs",
                    "-b",
                    str(TEST_BLOCK_NUMBER),
                    "--data-dir",
                    str(temp_data_dir),
                    "--body-chunk-size",
                    "10",
                ],
            )

        self.helper.assert_success_with_message(
            result, "All AR inputs generated successfully"
        )

        # Check that the output files use the correct naming pattern
        for call in mock_trace.call_args_list:
            args, kwargs = call
            output_path = Path(kwargs["output_path"])
            filename = output_path.name

            # Should match the expected patterns
            assert (
                filename.endswith("_init")
                or filename.endswith("_teardown")
                or "_body_" in filename
                or filename.endswith("_aggregator")
            ), f"Unexpected filename pattern: {filename}"

    def test_generate_ar_inputs_command_with_cairo_pie(
        self, temp_data_dir, mock_generate_ar_setup
    ):
        """Test generate_ar_inputs with Cairo PIE output."""
        programs, patch_all_for_generate_ar = mock_generate_ar_setup

        with (
            patch("scripts.keth.run_generate_trace") as mock_trace,
            patch_all_for_generate_ar(),
        ):
            result = self.runner.invoke(
                app,
                [
                    "generate-ar-inputs",
                    "-b",
                    str(TEST_BLOCK_NUMBER),
                    "--data-dir",
                    str(temp_data_dir),
                    "--body-chunk-size",
                    "5",
                    "--cairo-pie",
                ],
            )

        self.helper.assert_success_with_message(
            result, "All AR inputs generated successfully"
        )

        # Verify cairo_pie parameter was passed correctly to all calls
        for call in mock_trace.call_args_list:
            args, kwargs = call
            assert kwargs["cairo_pie"] is True

        # Verify filenames contain cairo_pie pattern
        for call in mock_trace.call_args_list:
            args, kwargs = call
            output_path = Path(kwargs["output_path"])
            filename = output_path.name
            assert filename.startswith("cairo_pie_") and filename.endswith(
                ".zip"
            ), f"Expected Cairo PIE filename pattern, got: {filename}"

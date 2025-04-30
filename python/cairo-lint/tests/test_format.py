from pathlib import Path

import pytest
from cairo_lint.main import process_file

TEST_DATA_DIR = Path(__file__).parent / "test_data"


# Helper function to read expected content if it exists
def read_expected(base_name: str) -> str:
    expected_file = TEST_DATA_DIR / f"{base_name}_expected.cairo"
    if expected_file.exists():
        return expected_file.read_text()
    # If no explicit expected file, assume input should equal output
    input_file = TEST_DATA_DIR / f"{base_name}.cairo"
    return input_file.read_text()


# --- Test Cases ---


@pytest.mark.parametrize(
    "test_file_base, should_change",
    [
        # Cases where the file content should NOT change
        ("disabled_file", False),
        ("disabled_line_single", False),
        ("all_used", False),
        ("no_imports", False),
        ("empty_file", False),
        # Cases where the file content SHOULD change
        ("unused_multi_one", True),
        ("unused_single", True),
        ("unused_single_partial", True),
        ("multi_comma_last", True),
    ],
)
def test_formatting_scenarios(test_file_base: str, should_change: bool):
    """
    Tests various formatting scenarios using files from test_data.
    """
    input_file = TEST_DATA_DIR / f"{test_file_base}.cairo"
    original_content = input_file.read_text()
    expected_content = read_expected(test_file_base)

    result_content = process_file(input_file)

    if should_change:
        assert (
            result_content is not None
        ), f"File '{test_file_base}' was expected to change, but process_file returned None"
        # Compare line by line for better diff output in pytest
        assert result_content.splitlines() == expected_content.splitlines()
        assert (
            result_content == expected_content
        ), f"File '{test_file_base}' content mismatch after processing."
    else:
        assert (
            result_content is None
        ), f"File '{test_file_base}' was NOT expected to change, but process_file returned new content."
        # Verify original file wasn't somehow modified (good practice)
        assert (
            input_file.read_text() == original_content
        ), f"File '{test_file_base}' was modified unexpectedly."


# --- Optional: More specific tests if needed ---


def test_disabled_multi_item_specific():
    """Verify specific behavior for disabled multi-line item."""
    input_file = TEST_DATA_DIR / "disabled_line_multi_item.cairo"
    result = process_file(input_file)
    assert result is not None
    # Check that the disabled item remains
    assert "get_label_location" in result
    # Check that the other unused item is removed
    assert "from starkware.cairo.common.alloc import alloc" not in result
    # Check that the used item remains
    assert "get_fp_and_pc" in result


def test_disabled_multi_block_specific():
    """Verify specific behavior for disabled multi-line block."""
    input_file = TEST_DATA_DIR / "disabled_line_multi_block.cairo"
    result = process_file(input_file)
    assert result is not None
    # Check that the disabled block items remain
    assert "get_fp_and_pc" in result
    assert "get_label_location" in result
    # Check that the other unused item is removed
    assert "from starkware.cairo.common.alloc import alloc" not in result

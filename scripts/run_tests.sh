#!/bin/bash
#!/bin/bash
#
# run_tests.sh - Ethereum Block Test Runner
#
# Description:
#   This script automates the process of running tests for Ethereum blocks.
#   It iterates through JSON files representing blocks and runs tests for each one,
#   capturing the output in separate log files.
#
# Usage:
#   ./run_tests.sh
#
# Output:
#   - Creates log files named log_<block_number>.out for each tested block
#   - Logs progress and results to stdout
#
# Details:
#   The script uses a shell loop instead of pytest parametrize due to unresolved
#   out-of-memory issues. Each test is run as a separate process to isolate memory
#   usage and prevent OOM errors. Tests that have already been run (with existing
#   log files) are skipped to allow for resuming interrupted test runs.
#

# Directory containing the JSON files
DATA_DIR="data/1/eels"

# Iterate over all JSON files in the directory
for file in "$DATA_DIR"/*.json; do
	# Extract the filename without path and extension
	filename=$(basename "$file")
	block_number="${filename%.json}"

	# Check if log file already exists
	if [ -f "log_${block_number}.out" ]; then
		echo "Skipping block $block_number - log file already exists"
		continue
	fi

	echo "Starting test for block $block_number..."

	# Run the command in the background and redirect output to a log file
	(
		uv run pytest cairo/tests/ethereum/prague/test_fork.py -k "test_state_transition_eth_mainnet[$block_number]" --profile-cairo --no-skip-cached-tests -s >"log_${block_number}.out" 2>&1
		echo "Test for block $block_number completed. Output saved to log_${block_number}.out"
	)
done

# Wait for all remaining background processes to complete
wait

echo "All tests completed."

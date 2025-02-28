#!/bin/bash
#
# extract_cycles.sh - Ethereum Block Cycle Counter
#
# Description:
#   This script automates the process of collecting cycle counts for Ethereum blocks.
#   It iteratively runs zkpig generate and rsp to extract the RISC-V cycle counts for each successfully processed block.
#   The results are saved to a CSV file for further analysis.
#
# Usage:
#   ./extract_cycles.sh [duration_in_seconds]
#
# Parameters:
#   duration_in_seconds - Optional. The duration in seconds for which the script should run.
#                         Default is 3000 seconds (50 minutes) if not specified.
#
# Environment Variables:
#   CHAIN_RPC_URL - Required. The Ethereum RPC URL to connect to.
#                   Example: export CHAIN_RPC_URL=https://ethereum-mainnet.example.com/your_api_key
#
# Output:
#   - Creates or appends to cycle_counts.csv with format: block_number,cycles
#   - Logs progress and results to stdout
#
# Dependencies:
#   - zkpig - For generating provable executions
#   - rsp - For extracting cycle counts
#

# Check if CHAIN_RPC_URL environment variable is set
if [ -z "$CHAIN_RPC_URL" ]; then
	echo "Error: CHAIN_RPC_URL environment variable is not set"
	echo "Please set it with: export CHAIN_RPC_URL=your_ethereum_rpc_url"
	exit 1
fi

# Set default duration and check for command line argument
DEFAULT_DURATION=3000
DURATION=${1:-$DEFAULT_DURATION}

# Validate that duration is a positive integer
if ! [[ $DURATION =~ ^[0-9]+$ ]]; then
	echo "Error: Duration must be a positive integer (seconds)"
	echo "Usage: $0 [duration_in_seconds]"
	exit 1
fi

echo "Running with duration: $DURATION seconds"

START_TIME=$(date +%s)
END_TIME=$((START_TIME + DURATION))

# Create a header for the CSV file only if it doesn't exist
if [ ! -f cycle_counts.csv ]; then
	echo "Creating new CSV file with header..."
	echo "block_number,cycles" >cycle_counts.csv
else
	echo "Using existing CSV file: cycle_counts.csv"
fi

echo "Starting zkpig generate loop for $((DURATION / 60)) minutes..."

# Run zkpig generate in a loop for the specified duration
while [ $(date +%s) -lt $END_TIME ]; do
	echo "Running zkpig generate at $(date)"

	# Run zkpig generate and capture its output
	zkpig_output=$(zkpig generate --chain-rpc-url "$CHAIN_RPC_URL" 2>&1 | tee /dev/tty)
	echo "$zkpig_output"
	echo "zkpig generate completed at $(date)"

	# Extract the block number from the zkpig output
	block_number=$(echo "$zkpig_output" | grep "Provable execution succeeded" | grep -oE 'block.number": ([0-9]+)' | grep -oE "[0-9]+")

	echo "Detected block number: $block_number"

	# Check if this block has already been processed
	if ! grep -q "^$block_number," cycle_counts.csv; then
		echo "Processing new block number: $block_number"

		# Run rsp command and capture output
		output=$(rsp --block-number "$block_number" --rpc-url "$CHAIN_RPC_URL" 2>&1 | tee /dev/tty)

		# Extract cycle count using grep and sed
		cycles=$(echo "$output" | grep -A 1 "Execution report:" | grep "opcode counts" | sed -E 's/.*\(([0-9]+) total instructions\).*/\1/')

		if [ -n "$cycles" ]; then
			echo "Block $block_number: $cycles cycles"
			# Save to the CSV file
			echo "$block_number,$cycles" >>cycle_counts.csv
		else
			echo "Could not extract cycle count for block $block_number"
		fi
	else
		echo "Block $block_number already processed, skipping"
	fi

	# Small pause between runs to avoid overwhelming the system
	sleep 1
done

echo "Duration of $((DURATION / 60)) minutes completed. All blocks processed. Results saved to cycle_counts.csv"

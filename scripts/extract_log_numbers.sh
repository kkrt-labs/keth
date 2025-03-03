#!/bin/bash

#!/bin/bash
#
# extract_log_numbers.sh - Log Number Extractor for Test Results
#
# Description:
#   This script extracts log numbers from test output files.
#   It processes log files named in the format "log_<number>.out" and extracts
#   both the log identifier from the filename and the associated test number
#   from within the file content.
#   The results are saved to a CSV file for further analysis.
#
# Usage:
#   ./extract_log_numbers.sh
#
# Output:
#   - Creates log_numbers.csv with format: log_file,number
#   - Each row contains the log identifier and the associated test number
#
# Details:
#   The script searches for lines containing ".py" followed by a number in each log file,
#   which indicates the test run identifier. It extracts this number along with the
#   log file's own identifier (from its filename) and records the correlation.
#   This allows for tracking which test runs correspond to which log files.
#
echo "log_file,number" >log_numbers.csv

# Find all log files and process them
for log_file in log_*.out; do
	# Extract the line containing the pattern ".py" followed by a number
	line=$(grep -E "\.py [0-9]+" "$log_file" | head -1)

	if [ -n "$line" ]; then
		# Extract the number
		number=$(echo "$line" | grep -oE "[0-9]+$")

		# Extract just the number from the log filename
		log_number=$(echo "$log_file" | grep -oE "[0-9]+")

		# Add to CSV
		echo "$log_number,$number" >>log_numbers.csv
	fi
done

echo "Results saved to log_numbers.csv"

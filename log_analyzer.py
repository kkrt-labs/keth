#!/usr/bin/env python3
import os
import re
import subprocess
import sys
from datetime import datetime


def run_test_and_capture_output(test_path):
    """Run the test command and capture its stdout."""
    command = (
        f"uv run pytest '{test_path}' -s --log-cli-level=TRACE --no-skip-cached-tests"
    )
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        shell=True,
        cwd=os.getcwd(),  # Explicitly use current directory
    )

    output = ""
    if process.stdout:
        for line in process.stdout:
            output += line
            print(line, end="")  # Echo output in real-time

    process.wait()
    return output


def read_log_file(file_path):
    """Read log content from a file."""
    print(f"Reading logs from file: {file_path}")
    try:
        with open(file_path, "r") as f:
            return f.read()
    except Exception as e:
        print(f"Error reading file: {e}")
        sys.exit(1)


def extract_log_entries(output):
    """Extract [CAIRO] and [EELS] log entries from the output."""
    cairo_logs = []
    eels_logs = []

    for line in output.splitlines():
        if "[CAIRO]" in line:
            cairo_logs.append(line.strip())
        elif "[EELS]" in line:
            eels_logs.append(line.strip())

    return cairo_logs, eels_logs


def parse_opcode(log_line):
    """Extract opcode from a log line."""
    if "0x" in log_line:
        # Extract the hexadecimal opcode
        match = re.search(r"0x[0-9a-fA-F]+", log_line)
        if match:
            return match.group(0).lower()  # Normalize to lowercase
    return None


def generate_markdown_table(cairo_logs, eels_logs):
    """Generate a markdown table comparing CAIRO and EELS logs."""
    # Generate the table
    table = "| CAIRO | EELS | VALID |\n"
    table += "|-------|------|-------|\n"

    # Track statistics
    stats = {
        "total_cairo": len(cairo_logs),
        "total_eels": len(eels_logs),
        "matched": 0,
        "unmatched_cairo": 0,
    }

    # Process all CAIRO logs
    from itertools import zip_longest

    for cairo_log, eels_log in zip_longest(cairo_logs, eels_logs):
        if not cairo_log:
            cairo_log = "[CAIRO] NONE"
        if not eels_log:
            eels_log = "[EELS] NONE"

        # Extract the content from the log lines by removing the prefix tags
        cairo_log = cairo_log.split("[CAIRO]")[1].strip()
        eels_log = eels_log.split("[EELS]")[1].strip()

        if cairo_log == eels_log:
            valid = "✅"
            stats["matched"] += 1
        else:
            valid = "❌"
            stats["unmatched_cairo"] += 1

        table += f"| {cairo_log} | {eels_log} | {valid} |\n"

    # Add summary statistics to the table
    table += "\n## Summary\n\n"
    table += f"- Total CAIRO logs: {stats['total_cairo']}\n"
    table += f"- Total EELS logs: {stats['total_eels']}\n"
    table += f"- Matched operations: {stats['matched']}\n"
    table += f"- Unmatched CAIRO logs: {stats['unmatched_cairo']}\n"

    # Calculate match percentage
    total_ops = stats["total_cairo"] + stats["total_eels"] - stats["matched"]
    match_percentage = (stats["matched"] / total_ops * 100) if total_ops > 0 else 0
    table += f"- Match percentage: {match_percentage:.2f}%\n"

    return table


def save_to_file(content, test_name=None):
    """Save the markdown table to a file."""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    # Create logs directory if it doesn't exist
    os.makedirs("logs", exist_ok=True)

    # Generate filename
    if test_name:
        # Extract test name from the command if possible
        filename = f"logs/log_analysis_{test_name}_{timestamp}.md"
    else:
        filename = f"logs/log_analysis_{timestamp}.md"

    with open(filename, "w") as f:
        f.write(content)
    print(f"Analysis saved to {filename}")
    return filename


def extract_test_name(command):
    """Extract test name from the test command."""
    # Try to extract test name from pytest command
    match = re.search(r"test_([a-zA-Z0-9_]+)", command)
    if match:
        return match.group(1)
    return None


def print_usage():
    """Print usage instructions."""
    print("Usage:")
    print("  1. Run a test and analyze logs:")
    print("     python log_analyzer.py 'test_path'")
    print("  2. Analyze logs from a file:")
    print("     python log_analyzer.py --file path/to/logfile.txt")
    print("  3. Show this help message:")
    print("     python log_analyzer.py --help")


def main():
    if len(sys.argv) < 2 or sys.argv[1] == "--help" or sys.argv[1] == "-h":
        print_usage()
        sys.exit(0)

    # Check if we're analyzing a file
    if sys.argv[1] == "--file" or sys.argv[1] == "-f":
        if len(sys.argv) < 3:
            print("Error: No file path provided.")
            print_usage()
            sys.exit(1)

        file_path = sys.argv[2]
        output = read_log_file(file_path)
        test_name = os.path.basename(file_path).split(".")[0]
    else:
        # Run the test command
        test_command = sys.argv[1]
        test_name = extract_test_name(test_command)
        output = run_test_and_capture_output(test_command)

    cairo_logs, eels_logs = extract_log_entries(output)
    print(f"Found {len(cairo_logs)} CAIRO logs and {len(eels_logs)} EELS logs")

    if not cairo_logs and not eels_logs:
        print("No logs found. Make sure the test outputs [CAIRO] and [EELS] logs.")
        sys.exit(1)

    # Generate the markdown table
    table = generate_markdown_table(cairo_logs, eels_logs)

    # Save to file and print
    filename = save_to_file(table, test_name)

    print("\nMarkdown Table Summary:")
    # Print just the summary part
    summary_lines = (
        table.split("## Summary")[1].strip() if "## Summary" in table else ""
    )
    print(f"## Summary\n{summary_lines}")
    print(f"\nFull analysis saved to {filename}")


if __name__ == "__main__":
    main()

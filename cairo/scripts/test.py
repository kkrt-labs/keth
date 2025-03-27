def test_fast():
    import os
    import subprocess
    import sys

    # Copy the environment and tweak it
    env = os.environ.copy()
    env["HYPOTHESIS_PROFILE"] = "fast"
    env["PYTHONUNBUFFERED"] = "1"  # Ensure unbuffered output for colors
    if "TERM" not in env:
        env["TERM"] = "xterm-256color"  # Ensure terminal supports colors

    try:
        # Run the command without capturing output, letting it go directly to the terminal
        result = subprocess.run(
            "uv run pytest -n logical -m 'not slow' -v -s --no-skip-cached-tests --ignore-glob=cairo/tests/ef_tests/ --no-coverage",
            shell=True,
            env=env,
            check=False,  # Don't raise an exception immediately
        )

        # Check the return code
        if result.returncode != 0:
            print(f"Command failed with exit code {result.returncode}", file=sys.stderr)
            return result.returncode

        return 0
    except Exception as e:
        print(f"Error executing test: {e}", file=sys.stderr)
        return 1


def test_unit():
    import os
    import subprocess
    import sys

    # Copy the environment and tweak it
    env = os.environ.copy()
    env["PYTHONUNBUFFERED"] = "1"  # Ensure unbuffered output for colors
    if "TERM" not in env:
        env["TERM"] = "xterm-256color"  # Ensure terminal supports colors

    try:
        # Run the command without capturing output, letting it go directly to the terminal
        result = subprocess.run(
            "uv run pytest -n logical -v -s --no-skip-cached-tests --ignore-glob=cairo/tests/ef_tests/ --no-coverage",
            shell=True,
            env=env,
            check=False,
        )

        # Check the return code
        if result.returncode != 0:
            print(f"Command failed with exit code {result.returncode}", file=sys.stderr)
            return result.returncode

        return 0
    except Exception as e:
        print(f"Error executing test: {e}", file=sys.stderr)
        return 1


def test_ef():
    import os
    import subprocess
    import sys
    import time

    # Use current timestamp as seed
    seed = str(int(time.time()))

    # Copy the environment and tweak it
    env = os.environ.copy()
    env["PYTHONUNBUFFERED"] = "1"  # Ensure unbuffered output for colors
    if "TERM" not in env:
        env["TERM"] = "xterm-256color"  # Ensure terminal supports colors

    try:
        # Run the command without capturing output, letting it go directly to the terminal
        result = subprocess.run(
            f"uv run pytest -n logical -v -s --no-skip-cached-tests -m 'not slow' --max-tests=5000 --randomly-seed={seed} cairo/tests/ef_tests/",
            shell=True,
            env=env,
            check=False,
        )

        # Check the return code
        if result.returncode != 0:
            print(f"Command failed with exit code {result.returncode}", file=sys.stderr)
            return result.returncode

        return 0
    except Exception as e:
        print(f"Error executing test: {e}", file=sys.stderr)
        return 1

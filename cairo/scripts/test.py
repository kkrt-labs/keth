def test_fast():
    import os
    import subprocess

    # Copy the environment and tweak it
    env = os.environ.copy()
    env["HYPOTHESIS_PROFILE"] = "fast"
    env["PYTHONUNBUFFERED"] = "1"  # Ensure unbuffered output for colors
    if "TERM" not in env:
        env["TERM"] = "xterm-256color"  # Ensure terminal supports colors

    subprocess.run(
        "uv run pytest -n logical -v -s --no-skip-cached-tests --ignore-glob=cairo/tests/ef_tests/ --no-coverage",
        shell=True,
        env=env,
        check=True,
    )


def test_unit():
    import os
    import subprocess

    # Copy the environment and tweak it
    env = os.environ.copy()
    env["PYTHONUNBUFFERED"] = "1"  # Ensure unbuffered output for colors
    if "TERM" not in env:
        env["TERM"] = "xterm-256color"  # Ensure terminal supports colors

    subprocess.run(
        "uv run pytest -n logical -v -s --no-skip-cached-tests --ignore-glob=cairo/tests/ef_tests/ --no-coverage",
        shell=True,
        env=env,
        check=True,
    )


def test_ef():
    import os
    import subprocess

    # use current timestamp as seed
    seed = str(int(os.time.time()))

    # Copy the environment and tweak it
    env = os.environ.copy()
    env["PYTHONUNBUFFERED"] = "1"  # Ensure unbuffered output for colors
    if "TERM" not in env:
        env["TERM"] = "xterm-256color"  # Ensure terminal supports colors

    subprocess.run(
        f"uv run pytest -n logical -v -s --no-skip-cached-tests -m 'not slow' --max-tests=8000 --randomly-seed={seed} cairo/tests/ef_tests/ --ignore-glob='cairo/tests/ef_tests/fixtures/*'",
        shell=True,
        env=env,
        check=True,
    )

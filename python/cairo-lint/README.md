# Cairo Lint

A CLI tool to format Cairo files, starting with removing unused imports.

## Installation

Install using pip or uv:

```bash
pip install .
# or
uv pip install .
```

## Usage

Format files in place:

```bash
cairo-lint format path/to/your/code
cairo-lint format path/to/file.cairo
```

Check for formatting issues without modifying files:

```bash
cairo-lint format --check path/to/your/code
```

## Configuration

The tool can be configured by adding a `[tool.cairo-lint]` section to the
`pyproject.toml` file. For now, the only option is to exclude directories from
being linted.

```toml
[tool.cairo-lint]
exclude_dirs = ["python/cairo-lint/tests/test_data"]
```

Inside cairo files, you can use the `// cairo-lint: disable` directive to
disable the linter for a specific line, and the `// cairo-lint: disable-file`
directive to disable the linter for the entire file.

```cairo
// cairo-lint: disable
let x = 1;
```

```cairo
// cairo-lint: disable-file
```

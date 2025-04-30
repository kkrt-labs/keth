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

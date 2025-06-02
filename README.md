# keth

[![codecov](https://codecov.io/gh/kkrt-labs/keth/branch/main/graph/badge.svg?token=l3KEAeknXB)](https://codecov.io/gh/kkrt-labs/keth)

## Introduction

Keth is an open-source, proving backend for the Ethereum Execution Layer built
with [Kakarot Core EVM](https://github.com/kkrt-labs/kakarot) and
[Starkware's provable VM, Cairo](https://book.cairo-lang.org/).

Keth makes it possible to prove a given state transition asynchronously by:

- pulling pre-state,
- executing all required transactions,
- computing post-state

For instance, this can be run for a given block to prove the Ethereum protocol's
State Transition Function (STF).

## Getting Started

### Requirements

The project uses [uv](https://github.com/astral-sh/uv) to manage python
dependencies and run commands. To install uv:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Moreover, the project uses [rust](https://www.rust-lang.org/) to manage rust
dependencies.

### Installation

Everything is managed by uv, see [the uv docs](https://docs.astral.sh/uv/) for
the full documentation.

Apart from `uv`, you just need to copy the `.env.example` file to `.env`, making
sure to set the `CAIRO_PATH` environment variable to the path to the cairo
libraries. To have cairo-ls working, you need to `source .env` before even
opening your IDE. To avoid doing this manually, you can add the following to
your shell's rc file:

```bash
cd() {
    builtin cd "$@" || return

    if [ -f "$PWD/.env" ]; then
        echo "Loading environment variables from $PWD/.env"
        source "$PWD/.env"
    fi
}
```

This will automatically source the `.env` file when you `cd` into a directory
containing it. You can also update this to load only when you enter the keth
directory.

Additionally, you can set the `LOG_FORMAT` environment variable to control the
output format of logs from the Rust components. Supported values are:

- `plain` (default): Human-readable, colored log output.
- `json`: Structured JSON logging, useful to be stored.

## Usage

Keth provides two main CLI tools for different use cases.

First, you'll need to compile the Cairo programs.

```bash
uv run compile_keth
```

### Keth CLI (`uv run keth`)

The main Keth CLI for generating execution traces and proofs for Ethereum blocks
using STWO.

#### Commands

- **`trace`** - Generate execution traces from Ethereum block data

  - Uses ZK-PI (Zero-Knowledge Prover Input) data to create block execution
    traces
  - Supports different execution steps: `main` (run everything sequentially),
    `init`, `body`, `teardown`, `aggregator`.
  - Can output traces as prover inputs JSON, binary files, or Cairo PIE files

- **`prove`** - Generate STWO proofs from prover input files

  - Takes prover input information and generates cryptographic proofs
  - Supports Cairo-compatible serialization format to verify the proof in a
    Cairo program

- **`verify`** - Verify generated proofs

  - Validates proof correctness using the Rust STWO verifier

- **`e2e`** - End-to-end pipeline (trace + prove + verify)

  - Runs the complete workflow without intermediate file I/O
  - Optionally includes proof verification
  - Has high RAM requirements, and is not recommended for regular sized blocks

- **`generate-ar-inputs`** - Generate all prover inputs / Cairo PIEs for an
  Applicative Recursion run.
  - Creates all necessary traces for recursive proving
  - Automatically chunks body transactions for efficient processing
  - Outputs a Cairo PIE file for each step.

#### Example Usage

```bash
# Generate a trace for block 22616014
uv run keth trace -b 22616014

# Run end-to-end pipeline with verification
uv run keth e2e -b 22616014 --verify

# Generate all AR Cairo PIEs for recursive proving
uv run keth generate-ar-inputs -b 22616014 --cairo-pie
```

### Prove Cairo CLI (`uv run prove-cairo`)

A tool for running and proving arbitrary Cairo programs.

#### Commands

- **`run-and-prove`** - Execute Cairo programs and generate proofs
  - Runs compiled Cairo programs with specified entrypoints and arguments
  - Generates execution traces and STWO proofs
  - Optionally verifies the generated proof

#### Example Usage

```bash
uv run prove-cairo --compiled-program cairo/tests/programs/fibonacci.json --arguments 1,1,20000
```

## Generating Proofs for Ethereum Blocks

To generate a proof for an Ethereum block, you'll need:

1. **Prover inputs (ZK-PI)** for the given block, generated with Kakarot's
   [ZK-PIG](https://github.com/kkrt-labs/zk-pig)
2. **The compiled Keth program** (`uv run compile_keth`)

### Requirements

- Block must be of Cancun fork (until Prague changes are merged)
- ZKPI data must be available as a JSON file
- Compiled Cairo program must exist at the specified path

### Quick Start

```bash
# Generate proof for a specific block
uv run keth e2e -b <BLOCK_NUMBER>

# Or use the legacy prove-block script
uv run prove-block <BLOCK_NUMBER>
```

Run `uv run keth --help` for detailed command options and parameters.

## Development

For development-specific information including testing, profiling, and
contributing guidelines, see [docs/development.md](docs/development.md).

## Architecture Diagram

Coming soon 🏗️.

## Acknowledgements

- Ethereum Foundation: We are grateful to the Ethereum Foundation for the python
  execution specs and tests.

## Status

Keth is a work in progress (WIP ⚠️) and as such is not suitable for production.

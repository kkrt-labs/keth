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

## Getting started

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

### Running tests

```bash
uv run pytest <optional pytest args>
```

Some tests require to compile solidity code, which requires `forge` to be
installed, and `foundry` to be in the path, and to run `forge build`.

#### Ethereum Foundation Tests

We adapted the testing framework from the
[Ethereum Execution Specs](https://github.com/ethereum/execution-specs) to be
able to run on Keth. These tests are located in the `cairo/tests/ef_tests`
directory. For now, only the State Transition tests are implemented. You can run
them with:

```bash
uv run pytest cairo/tests/ef_tests/cancun/test_state_transition.py
```

#### Ethereum Mainnet Tests

To run the `state_transition` function against a given Ethereum Mainnet block,
you'll need first to generate the Prover Input (ZK-PI) for this block using
[ZK-PIG](https://github.com/kkrt-labs/zk-pig):

```bash
zkpig generate
```

This will generate the ZK-PI for the given block and save it in the `data/1/`
directory. Then, you'll need to run

```bash
uv run zkpi_to_eels data/1/preflight/
```

to convert the ZK-PI to the EELS format, actually generating data in the
`data/1/eels` directory.

Then, you can run the tests with:

```bash
uv run pytest cairo/tests/ethereum/cancun/test_fork.py -k "test_state_transition_eth_mainnet"
```

### Proving a Block

To generate a proof for an Ethereum block, use the `prove_block.py` script:

```bash
uv run prove-block <BLOCK_NUMBER>
```

```bash
usage: prove-block [-h] [--output-dir OUTPUT_DIR] [--data-dir DATA_DIR] [--compiled-program COMPILED_PROGRAM]
                   block_number
```

Requirements:

- Block must be post-Cancun fork (block number ≥ 19426587)
- ZKPI data must be available as a JSON file
- Compiled Cairo program must exist at the specified path (you can run
  `cairo-compile --proof_mode cairo/ethereum/cancun/main.cairo --cairo_path=cairo --no_debug_info --output build/main_compiled.json`
  for that)

The script will load the ZKPI data for the specified block, convert it to the
format required by Keth, run the proof generation process, and save proof
artifacts to the output directory.

### Updating Rust dependencies

Any changes to the rust code requires a re-build and re-install of the python
package, see
[the uv docs](https://docs.astral.sh/uv/concepts/projects/init/#projects-with-extension-modules)
for more information.

The tl;dr is:

```bash
uv run --reinstall <command>
```

Forgetting the `--reinstall` flag will not re-build the python package and
consequentially not use any changes to the rust code.

## Status

Keth is a work in progress (WIP ⚠️) and as such is not suitable for production.

## Architecture Diagram

Coming soon 🏗️.

## Acknowledgements

- Ethereum Foundation: We are grateful to the Ethereum Foundation for the python
  execution specs and tests.

# keth

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

- Herodotus: thanks to Herodotus team for SHARP SDK libraries.

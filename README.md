# keth

## Introduction

Keth is an open-source, proving backend for the Ethereum Execution Layer built with
[Kakarot Core EVM](https://github.com/kkrt-labs/kakarot) and
[Starkware's provable VM, Cairo](https://book.cairo-lang.org/).

Keth makes it possible to prove a given state transition asynchronously by:

- pulling pre-state,
- executing all required transactions,
- computing post-state

For instance, this can be run for a given block to prove the Ethereum protocol's State Transition Function (STF).

## Getting started

### Requirements

The project uses [uv](https://github.com/astral-sh/uv) to manage python
dependencies and run commands. To install uv:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Moreover, the project uses [rust](https://www.rust-lang.org/) to manage rust dependencies.


## Status

Keth is a work in progress (WIP ⚠️) and as such is not suitable for production.

## Architecture Diagram

Coming soon 🏗️.

## Acknowledgements

- Herodotus: thanks to Herodotus team for SHARP SDK libraries.

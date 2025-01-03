# Cairo Addons

A collection of Cairo "addons", ie. cairo tools and libraries not part of the
Starkware core library.

## Installation

As any uv workspace, you can install the package with:

```bash
uv sync
```

## Updating Rust dependencies

To update the rust dependencies, you can run:

```bash
maturin develop --uv
```

Then, running `uv run python ...` should have the changes reflected.

# keth-run

A Rust binary that mimics the functionality of `cairo/scripts/prove_block.py`
for generating STARK proofs for Ethereum blocks using Cairo. This crate serves
as a bridge between the Rust and Python components of the Keth project, it is
primarily used for profiling cairo-vm.

## Important note

This crate uses a custom `build.rs` script to properly set up the Python
environment variables.

The script needs to be modified to match your Python environment. Specifically,
you may need to update the following environment variables:

1. `PYTHONPATH`: This should point to your Python virtual environment's
   site-packages directory and the various Python source directories used by
   Keth. No need to change this (it's the same as .env.example's `CAIRO_PATH`
   value)
2. `PYO3_PYTHON`: This should point to your Python interpreter executable.
3. `PYTHONHOME`: This should point to your Python installation directory, in
   order to find "global" modules (e.g.: encodings). If your installation is
   managed by `uv`, you don't need to change anything.

## Run

From the workspace root:

```bash
cargo r -p keth-run <BLOCK_NUMBER>
```

- If you want to generate a flamegraph (assuming you have `cargo flamegraph`
  installed):

```bash
cargo flamegraph --root -p keth-run -- <BLOCK_NUMBER>
```

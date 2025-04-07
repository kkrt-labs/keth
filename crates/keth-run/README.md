# keth-run

A Rust binary that mimics the functionality of `cairo/scripts/prove_block.py`
for generating STARK proofs for Ethereum blocks using Cairo. This crate serves
as a bridge between the Rust and Python components of the Keth project, it is
primarily used for profiling cairo-vm.

## Run

- From the workspace root:

```bash
cargo r -p keth-run <BLOCK_NUMBER>
```

- If you want to generate a flamegraph (assuming you have `cargo flamegraph`
  installed):

```bash
cargo flamegraph --root -p keth-run -- <BLOCK_NUMBER>
```

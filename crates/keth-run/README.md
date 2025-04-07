# keth-run

A Rust binary that mimics the functionality of `cairo/scripts/prove_block.py`.
It is primarily used for profiling cairo-vm.

## Run

- From the workspace root:

```bash
cargo r -p keth-run <BLOCK_NUMBER>
```

- To generate a flamegraph.svg file (requires sudo access) using
  [flamegraph](https://github.com/flamegraph-rs/flamegraph):

```bash
cargo flamegraph --root -p keth-run -- <BLOCK_NUMBER>
```

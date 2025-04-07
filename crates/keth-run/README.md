# keth-run

A Rust binary that mimics the functionality of `cairo/scripts/prove_block.py`. It is
primarily used for profiling cairo-vm.

## Run

- From the workspace root:

```bash
cargo r -p keth-run <BLOCK_NUMBER>
```

- If you want to generate a
  [flamegraph](https://github.com/brendangregg/FlameGraph), (unless you're not
  using a MacOS) you'll need root privileges. Since the required environment
  vars are not preserved, you need to redefine them manually for the sudo
  command.

```bash
cargo build -p keth-run --release
sudo PYTHONPATH=$PYTHONPATH PYTHONHOME=$PYTHONHOME PYO3_PYTHON=$PYO3_PYTHON flamegraph -- target/release/keth-run <BLOCK_NUMBER>
```

# Development Guide

This guide covers development-specific topics for working with Keth.

## Running Tests

```bash
uv run pytest <optional pytest args>
```

Some tests require compiling Solidity code, which requires `forge` to be
installed, `foundry` to be in the path, and running `forge build`.

### Profiling Cairo Tests

To generate a profiling graph, you need to add `--profile-cairo` to your pytest
command. For example:

```bash
uv run pytest -k get_u384_bits_little --profile-cairo
```

```bash
# find the generated .prof file corresponding to your test execution
ls cairo/tests/ethereum/utils/test_numeric*.prof
-rw-r--r--@ 1 kkrt  staff   854B 31 mar 13:20 cairo/tests/ethereum/utils/test_numeric_get_u384_bits_little__1743420053085600000_5593df42.prof
```

```bash
# use snakeviz to display the graph in a browser web page
snakeviz cairo/tests/ethereum/utils/test_numeric_get_u384_bits_little__1743420053085600000_5593df42.prof
```

### Profiling Block Runs

To profile the non-cairo part, we can use
[samply](https://github.com/mstange/samply/). Example:

```bash
samply record uv run keth trace -b 22615247
```

### Ethereum Foundation Tests

We adapted the testing framework from the
[Ethereum Execution Specs](https://github.com/ethereum/execution-specs) to be
able to run on Keth. These tests are located in the `cairo/tests/ef_tests`
directory. For now, only the State Transition tests are implemented. You can run
them with:

```bash
uv run pytest cairo/tests/ef_tests/cancun/test_state_transition.py
```

### Ethereum Mainnet Tests

To run the `state_transition` function against a given Ethereum Mainnet block,
you'll need first to generate the Prover Input (ZK-PI) for this block using
[ZK-PIG](https://github.com/kkrt-labs/zk-pig):

```bash
zkpig generate
```

This will generate the ZK-PI for the given block and save it in the
`data/1/inputs` directory.

Then, you can run the tests with:

```bash
uv run pytest cairo/tests/ethereum/cancun/test_fork.py -k "test_state_transition_eth_mainnet"
```

## Updating Rust Dependencies

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

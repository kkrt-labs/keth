# Ethereum MPT Library

A Python library for working with Ethereum's Merkle Patricia Tries (MPT).

## Overview

This library provides the ability to:

- ✅ derive Ethereum partial state tries from
  [prover inputs](https://github.com/kkrt-labs/zk-pig).
- ⌛ transform an Ethereum partial state trie into an
  [EELS](https://github.com/ethereum/execution-specs/tree/master/src/ethereum/cancun)
  `State` object
- ⌛ compute the difference between two Ethereum partial state tries

## Quick Start

```python
from pathlib import Path

from mpt.ethereum_tries import EthereumTries

# Load tries from a JSON dump
tries = EthereumTries.from_json(Path("data/1/inputs/22074629.json"))
```

## License

MIT

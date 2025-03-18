# ETH-RPC Library

A lightweight Python Ethereum JSON-RPC client.

## Overview

This library provides a simple interface for making Ethereum RPC calls. Types
are shared with
[Ethereum Execution Layer Specification (EELS)](https://github.com/ethereum/execution-specs/tree/master/src/ethereum/cancun)
codebase as much as possible.

## Quick Start

```python
from eth_rpc import EthereumRPC
from ethereum.cancun.fork_types import Address, Bytes32, U64

# Connect to a node
eth = EthereumRPC("https://mainnet.infura.io/v3/YOUR_API_KEY")

# Get an account's code
code: Bytes = eth.get_code(Address(bytes.fromhex("0x00...00abcde")[2:]), U64(123))

# Get account & storage proofs
address = Address.fromhex("0x00...00abcde")[2:]
storage_keys = [Bytes32.fromhex("0x01...23456")[2:]]
block_number = U64(123)  # Optional
account_proof = eth.get_proof(
    address=address,
    storage_keys=storage_keys,
    block_number=block_number
)
```

## License

MIT

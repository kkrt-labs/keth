# Cairo Elliptic Curve Library

A Cairo library for elliptic curve operations, designed to work with the Ethereum and Kakarot ecosystem.

## Overview

This library provides efficient implementations of elliptic curve operations in Cairo, with support for:

- ✅ secp256k1 curve operations (used in Ethereum ECDSA signatures)  
- ✅ alt_bn128 curve operations (used in Ethereum pairing precompiles)
- ✅ ECDSA signature verification
- ✅ Utility functions for curve arithmetic and operations
- ✅ Circuit compilation for efficient proof generation

## Features

### Supported Curves

- **secp256k1**: The curve used for Ethereum account signatures
- **alt_bn128**: The curve used for pairing operations in Ethereum precompiles

### Operations

- Point addition, doubling, and scalar multiplication
- ECDSA signature verification
- Circuit optimizations for efficient proving

## Quick Start

```python
from cairo_ec.curve import load_secp256k1_curve, EcPoint
from cairo_ec.ec_ops import ec_add, ec_mul

# Load the secp256k1 curve
curve = load_secp256k1_curve()

# Create points on the curve
p1 = EcPoint(x=..., y=...)
p2 = EcPoint(x=..., y=...)

# Point addition
result = ec_add(p1, p2, curve.prime)

# Scalar multiplication
scalar = 123
product = ec_mul(scalar, p1, curve.prime)
```

## Command Line Tools

The package includes a command-line tool for compiling EC circuits:

```bash
compile_circuit --input input_file.cairo --output compiled_circuit.json
```

## Integration with Keth/Kakarot

This library serves as a core component of the Keth proving backend, providing the elliptic curve operations needed for verifying Ethereum transactions and signatures within Cairo proofs.

## Development

To set up the development environment:

```bash
uv sync
```

To run tests:

```bash
uv run pytest tests/
```

## License

MIT

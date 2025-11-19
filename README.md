# Zevm

Zig implementation of the Ethereum Virtual Machine (EVM).

## Overview

Zevm is built from the ground up in Zig with the following goals:

- **Correctness**: Pass the official Ethereum test suite
- **Performance**: Competitive with state-of-the-art implementations (revm, geth, evmone)
- **Readability**: Serve as a clear reference implementation in idiomatic Zig
- **Extensibility**: Multi-chain support for Ethereum L2s (Optimism, Arbitrum, etc.)

## Status

Nested contract calls are working! 

CALL, DELEGATECALL, and STATICCALL all implemented with correct gas semantics. 

Storage (SLOAD/SSTORE), logging (LOG0-4), and contract creation (CREATE/CREATE2) are the remaining pieces.
Once those land, we can run the official Ethereum test suite end-to-end.

## Quickstart

```bash
# Build the project
zig build

# Run tests
zig build test

# Run benchmarks
zig build bench
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for detailed testing and benchmarking options.

## References

**Ethereum Specifications:**
- [Ethereum Yellow Paper](https://ethereum.github.io/yellowpaper/paper.pdf) - Formal specification
- [Jello Paper](https://jellopaper.org/) - More readable specification
- [EVM Opcodes](https://www.evm.codes/) - Interactive opcode reference

**Reference Implementations:**
- [Revm](https://github.com/bluealloy/revm) (Rust)
- [Geth](https://github.com/ethereum/go-ethereum) (Go)
- [Evmone](https://github.com/ipsilon/evmone) (C++)
- [Execution Specs](https://github.com/ethereum/execution-specs) (Python)

# Zevm

Zig implementation of the Ethereum Virtual Machine (EVM).

## Overview

Zevm is built from the ground up in Zig with the following goals:

- **Correctness**: Pass the official Ethereum test suite
- **Performance**: Competitive with state-of-the-art implementations (revm, geth, evmone)
- **Readability**: Serve as a clear reference implementation in idiomatic Zig
- **Extensibility**: Multi-chain support for Ethereum L2s (Optimism, Arbitrum, etc.)

## Status

Building an EVM from scratch in Zig. Core interpreter is working great – you can run bytecode with loops, math, memory, and control flow. Just finished the host abstraction layer, which unblocks a ton of cool stuff (environmental opcodes, storage, contract calls).

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

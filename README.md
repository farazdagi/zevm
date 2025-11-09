# Zevm

Zig implementation of the Ethereum Virtual Machine (EVM).

## Overview

Zevm is built from the ground up in Zig with the following goals:

- **Correctness**: Pass the official Ethereum test suite
- **Performance**: Competitive with state-of-the-art implementations (revm, geth, evmone)
- **Readability**: Serve as a clear reference implementation in idiomatic Zig
- **Extensibility**: Multi-chain support for Ethereum L2s (Optimism, Arbitrum, etc.)

## Status

**Implementation progress: 52/145 opcodes (36%)**

Currently implemented:
- Stack operations (PUSH, POP, DUP1-16, SWAP1-16)
- Arithmetic operations (ADD, MUL, SUB, DIV, MOD, EXP, SIGNEXTEND, etc.)
- Comparison & bitwise operations (LT, GT, EQ, AND, OR, XOR, SHL, SHR, SAR, etc.)
- Memory operations (MLOAD, MSTORE, MSTORE8, MSIZE)
- All 20 Ethereum hardforks (FRONTIER through OSAKA)
- Gas metering foundation with memory expansion costs
- Comprehensive test coverage (363 tests)

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

## Roadmap

Development is organized into thematic sprints:

- **Core opcodes** - Memory operations, environmental information, block context
- **Hashing & cryptography** - KECCAK256, signature verification
- **State management** - Storage operations (SLOAD/SSTORE), account handling
- **External calls** - CALL, STATICCALL, DELEGATECALL, contract creation
- **Multi-chain support** - Optimism-specific extensions (L1 data fees, system contracts)
- **Testing & validation** - Ethereum official test suite, Optimism test suite

## Architecture

High-level components:

- **Primitives** - Address, U256, B256, Bytes, Stack, Memory
- **Interpreter** - Fetch-decode-execute loop, opcode handlers, PC management
- **Spec Handler** - Hardfork management, fork-specific gas costs and features
- **Gas System** - Base costs, memory expansion, fork-aware calculations
- **Host** (planned) - Abstract interface between EVM and state backend

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

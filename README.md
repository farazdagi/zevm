# Zevm

Zevm is an implementation of the Ethereum Virtual Machine (EVM) written in Zig.

The goal is to create a concise and readable implementation in idiomatic Zig, with performance on par with the state of the art EVM implementations.

## Status

Getting closer to wrapping up the core functionality! 

One opcode (SELFDESTRUCT) and pre-compiles are the remaining pieces.
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

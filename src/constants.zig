/// Maximum operand stack depth as defined by the Ethereum specification.
/// This limits the number of 256-bit values on the operand stack during execution.
pub const STACK_LIMIT: usize = 1024;

/// Maximum call depth as defined by the Ethereum specification.
/// This limits the number of nested contract calls (CALL, DELEGATECALL, STATICCALL, CREATE, etc.).
pub const CALL_DEPTH_LIMIT: usize = 1024;

/// Number of block hashes that EVM can access in the past (pre-Prague).
pub const BLOCK_HASH_HISTORY: u64 = 256;

/// Keccak-256 hash of empty string.
/// keccak256("") = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470
pub const EMPTY_KECCAK256: [32]u8 = [_]u8{
    0xc5, 0xd2, 0x46, 0x01, 0x86, 0xf7, 0x23, 0x3c,
    0x92, 0x7e, 0x7d, 0xb2, 0xdc, 0xc7, 0x03, 0xc0,
    0xe5, 0x00, 0xb6, 0x53, 0xca, 0x82, 0x27, 0x3b,
    0x7b, 0xfa, 0xd8, 0x04, 0x5d, 0x85, 0xa4, 0x70,
};

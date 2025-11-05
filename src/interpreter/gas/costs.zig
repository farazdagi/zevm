//! Base EVM gas cost assignments.
//!
//! Most values are from "Appendix G. Fee Schedule" of the Yellow Paper.
pub const Costs = struct {
    // Base Tier Costs
    pub const ZERO: u64 = 0;
    pub const BASE: u64 = 2;
    pub const VERYLOW: u64 = 3;
    pub const LOW: u64 = 5;
    pub const MID: u64 = 8;
    pub const HIGH: u64 = 10;

    // Specific Opcode Costs
    pub const JUMPDEST: u64 = 1;
    pub const PUSH0: u64 = 2; // EIP-3855

    // Memory Operations
    pub const MLOAD: u64 = VERYLOW;
    pub const MSTORE: u64 = VERYLOW;
    pub const MSTORE8: u64 = VERYLOW;
    pub const MEMORY: u64 = VERYLOW; // Paid for every additional word when expanding memory.

    // Stack Operations
    pub const PUSH: u64 = VERYLOW;
    pub const POP: u64 = BASE;
    pub const DUP: u64 = VERYLOW;
    pub const SWAP: u64 = VERYLOW;

    // Arithmetic Operations
    pub const ADD: u64 = VERYLOW;
    pub const SUB: u64 = VERYLOW;
    pub const MUL: u64 = LOW;
    pub const DIV: u64 = LOW;
    pub const SDIV: u64 = LOW;
    pub const MOD: u64 = LOW;
    pub const SMOD: u64 = LOW;
    pub const ADDMOD: u64 = MID;
    pub const MULMOD: u64 = MID;
    pub const EXP_BASE: u64 = 10;
    pub const EXP_BYTE: u64 = 50; // Per byte in exponent (post-EIP-160)
    pub const SIGNEXTEND: u64 = LOW;

    // Comparison & Bitwise Operations
    pub const LT: u64 = VERYLOW;
    pub const GT: u64 = VERYLOW;
    pub const SLT: u64 = VERYLOW;
    pub const SGT: u64 = VERYLOW;
    pub const EQ: u64 = VERYLOW;
    pub const ISZERO: u64 = VERYLOW;
    pub const AND: u64 = VERYLOW;
    pub const OR: u64 = VERYLOW;
    pub const XOR: u64 = VERYLOW;
    pub const NOT: u64 = VERYLOW;
    pub const BYTE: u64 = VERYLOW;
    pub const SHL: u64 = VERYLOW;
    pub const SHR: u64 = VERYLOW;
    pub const SAR: u64 = VERYLOW;

    // Hashing Operations
    pub const KECCAK256_BASE: u64 = 30;
    pub const KECCAK256_WORD: u64 = 6; // Per word of data

    // Environmental Information
    pub const ADDRESS: u64 = BASE;
    pub const BALANCE: u64 = 100; // Warm access, cold is 2600
    pub const ORIGIN: u64 = BASE;
    pub const CALLER: u64 = BASE;
    pub const CALLVALUE: u64 = BASE;
    pub const CALLDATALOAD: u64 = VERYLOW;
    pub const CALLDATASIZE: u64 = BASE;
    pub const CALLDATACOPY_BASE: u64 = VERYLOW;
    pub const CALLDATACOPY_WORD: u64 = VERYLOW; // Per word copied
    pub const CALLDATA_ZERO_COST: u64 = 4; // Per zero byte in calldata
    pub const CODESIZE: u64 = BASE;
    pub const CODECOPY_BASE: u64 = VERYLOW;
    pub const CODECOPY_WORD: u64 = VERYLOW;
    pub const GASPRICE: u64 = BASE;
    pub const EXTCODESIZE: u64 = 100; // Warm, cold is 2600
    pub const EXTCODECOPY_BASE: u64 = 100; // Warm
    pub const EXTCODECOPY_WORD: u64 = VERYLOW;
    pub const RETURNDATASIZE: u64 = BASE;
    pub const RETURNDATACOPY_BASE: u64 = VERYLOW;
    pub const RETURNDATACOPY_WORD: u64 = VERYLOW;
    pub const EXTCODEHASH: u64 = 100; // Warm, cold is 2600

    // Block Information
    pub const BLOCKHASH: u64 = 20;
    pub const COINBASE: u64 = BASE;
    pub const TIMESTAMP: u64 = BASE;
    pub const NUMBER: u64 = BASE;
    pub const DIFFICULTY: u64 = BASE; // PREVRANDAO in post-merge
    pub const GASLIMIT: u64 = BASE;
    pub const CHAINID: u64 = BASE;
    pub const SELFBALANCE: u64 = LOW;
    pub const BASEFEE: u64 = BASE;

    // Storage Operations (EIP-2929/3529 warm/cold access costs)
    pub const SLOAD_WARM: u64 = 100;
    pub const SLOAD_COLD: u64 = 2100;
    pub const SSTORE_UNCHANGED: u64 = 100;
    pub const SSTORE_MODIFIED: u64 = 100;
    pub const SSTORE_NEW: u64 = 20000;
    pub const SSTORE_REFUND_CLEAR: u64 = 4800; // Refund when clearing storage

    // Control Flow
    pub const JUMP: u64 = MID;
    pub const JUMPI: u64 = HIGH;
    pub const PC: u64 = BASE;
    pub const MSIZE: u64 = BASE;
    pub const GAS: u64 = BASE;

    // Logging Operations
    pub const LOG_BASE: u64 = 375;
    pub const LOG_TOPIC: u64 = 375; // Per topic
    pub const LOG_DATA: u64 = 8; // Per byte of data

    // System Operations
    pub const CREATE_BASE: u64 = 32000;
    pub const CREATE2_BASE: u64 = 32000;
    pub const CREATE2_WORD: u64 = 6; // Per word of init code

    pub const CALL_BASE: u64 = 100; // Warm
    pub const CALL_COLD: u64 = 2600; // Cold account access
    pub const CALL_VALUE_TRANSFER: u64 = 9000; // If value > 0
    pub const CALL_NEW_ACCOUNT: u64 = 25000; // If creating new account
    pub const CALL_STIPEND: u64 = 2300; // Gas stipend for value transfers

    pub const DELEGATECALL_BASE: u64 = 100;
    pub const DELEGATECALL_COLD: u64 = 2600;

    pub const STATICCALL_BASE: u64 = 100;
    pub const STATICCALL_COLD: u64 = 2600;

    pub const RETURN: u64 = ZERO;
    pub const REVERT: u64 = ZERO;

    pub const SELFDESTRUCT_BASE: u64 = 5000;
    pub const SELFDESTRUCT_NEW_ACCOUNT: u64 = 25000;
    pub const SELFDESTRUCT_REFUND: u64 = 24000; // Pre-EIP-3529, now removed

    // Transient Storage (EIP-1153, Cancun+)
    pub const TLOAD: u64 = 100;
    pub const TSTORE: u64 = 100;

    // Blob Operations (EIP-4844, Cancun+)
    pub const BLOBHASH: u64 = VERYLOW;
    pub const BLOBBASEFEE: u64 = BASE;
};

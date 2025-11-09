const std = @import("std");

const arithmetic = @import("arithmetic.zig");
const bitwise = @import("bitwise.zig");
const comparison = @import("comparison.zig");
const control = @import("control.zig");
const crypto = @import("crypto.zig");
const environmental = @import("environmental.zig");
const logging = @import("logging.zig");
const memory = @import("memory.zig");
const storage = @import("storage.zig");
const system = @import("system.zig");
const test_helpers = @import("test_helpers.zig");

// ============================================================================
// Expose all operations directly from the module.
// ============================================================================

// Arithmetic operations
pub const opAdd = arithmetic.opAdd;
pub const opMul = arithmetic.opMul;
pub const opSub = arithmetic.opSub;
pub const opDiv = arithmetic.opDiv;
pub const opMod = arithmetic.opMod;
pub const opExp = arithmetic.opExp;
pub const opSignextend = arithmetic.opSignextend;
pub const opSdiv = arithmetic.opSdiv;
pub const opSmod = arithmetic.opSmod;
pub const opAddmod = arithmetic.opAddmod;
pub const opMulmod = arithmetic.opMulmod;

// Bitwise operations
pub const opAnd = bitwise.opAnd;
pub const opOr = bitwise.opOr;
pub const opXor = bitwise.opXor;
pub const opNot = bitwise.opNot;
pub const opByte = bitwise.opByte;
pub const opShl = bitwise.opShl;
pub const opShr = bitwise.opShr;
pub const opSar = bitwise.opSar;

// Comparison operations
pub const opLt = comparison.opLt;
pub const opGt = comparison.opGt;
pub const opSlt = comparison.opSlt;
pub const opSgt = comparison.opSgt;
pub const opEq = comparison.opEq;
pub const opIszero = comparison.opIszero;

// Control flow operations
pub const opPop = control.opPop;
pub const opStop = control.opStop;
pub const opJump = control.opJump;
pub const opJumpi = control.opJumpi;
pub const opJumpdest = control.opJumpdest;
pub const opPc = control.opPc;
pub const opGas = control.opGas;
pub const opReturn = control.opReturn;
pub const opRevert = control.opRevert;
pub const opInvalid = control.opInvalid;

// Cryptographic operations
pub const opKeccak256 = crypto.opKeccak256;

// Environmental operations - Transaction context
pub const opAddress = environmental.opAddress;
pub const opBalance = environmental.opBalance;
pub const opOrigin = environmental.opOrigin;
pub const opCaller = environmental.opCaller;
pub const opCallvalue = environmental.opCallvalue;
pub const opGasprice = environmental.opGasprice;
pub const opSelfbalance = environmental.opSelfbalance;

// Environmental operations - Calldata
pub const opCalldataload = environmental.opCalldataload;
pub const opCalldatasize = environmental.opCalldatasize;
pub const opCalldatacopy = environmental.opCalldatacopy;

// Environmental operations - Code
pub const opCodesize = environmental.opCodesize;
pub const opCodecopy = environmental.opCodecopy;
pub const opExtcodesize = environmental.opExtcodesize;
pub const opExtcodecopy = environmental.opExtcodecopy;
pub const opExtcodehash = environmental.opExtcodehash;

// Environmental operations - Return data
pub const opReturndatasize = environmental.opReturndatasize;
pub const opReturndatacopy = environmental.opReturndatacopy;

// Environmental operations - Block information
pub const opBlockhash = environmental.opBlockhash;
pub const opCoinbase = environmental.opCoinbase;
pub const opTimestamp = environmental.opTimestamp;
pub const opNumber = environmental.opNumber;
pub const opPrevrandao = environmental.opPrevrandao;
pub const opGaslimit = environmental.opGaslimit;
pub const opChainid = environmental.opChainid;
pub const opBasefee = environmental.opBasefee;
pub const opBlobhash = environmental.opBlobhash;
pub const opBlobbasefee = environmental.opBlobbasefee;

// Logging operations
pub const opLog0 = logging.opLog0;
pub const opLog1 = logging.opLog1;
pub const opLog2 = logging.opLog2;
pub const opLog3 = logging.opLog3;
pub const opLog4 = logging.opLog4;

// Memory operations
pub const opMload = memory.opMload;
pub const opMstore = memory.opMstore;
pub const opMstore8 = memory.opMstore8;
pub const opMsize = memory.opMsize;
pub const opMcopy = memory.opMcopy;

// Storage operations
pub const opSload = storage.opSload;
pub const opSstore = storage.opSstore;
pub const opTload = storage.opTload;
pub const opTstore = storage.opTstore;

// System operations
pub const opCreate = system.opCreate;
pub const opCreate2 = system.opCreate2;
pub const opCall = system.opCall;
pub const opCallcode = system.opCallcode;
pub const opDelegatecall = system.opDelegatecall;
pub const opStaticcall = system.opStaticcall;
pub const opSelfdestruct = system.opSelfdestruct;

test {
    std.testing.refAllDecls(@This());
    _ = arithmetic;
    _ = bitwise;
    _ = comparison;
    _ = control;
    _ = crypto;
    _ = environmental;
    _ = logging;
    _ = memory;
    _ = storage;
    _ = system;
    _ = test_helpers;
}

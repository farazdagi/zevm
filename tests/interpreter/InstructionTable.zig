const std = @import("std");
const zevm = @import("zevm");
const InstructionTable = zevm.interpreter.InstructionTable;
const Spec = zevm.hardfork.Spec;
const Hardfork = zevm.hardfork.Hardfork;

const expectError = std.testing.expectError;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "Creates table for all forks" {
    const forks = [_]Hardfork{
        .FRONTIER,
        .HOMESTEAD,
        .BYZANTIUM,
        .CONSTANTINOPLE,
        .ISTANBUL,
        .BERLIN,
        .LONDON,
        .SHANGHAI,
        .CANCUN,
        .PRAGUE,
    };

    for (forks) |fork| {
        const table = InstructionTable.forFork(fork);
        try expect(table.spec.fork == fork);
    }
}

test "FRONTIER has basic opcodes" {
    const table = InstructionTable.forFork(.FRONTIER);

    // Test that basic opcodes have handlers that are NOT unimplementedOpcodeHandler
    const info_stop = table.get(0x00); // STOP
    const info_add = table.get(0x01); // ADD
    const info_push1 = table.get(0x60); // PUSH1

    // These should have real handlers, not the invalid opcode handler
    const unimplemented_handler = InstructionTable.unimplementedOpcodeHandler;
    try expect(info_stop.handler != unimplemented_handler);
    try expect(info_add.handler != unimplemented_handler);
    try expect(info_push1.handler != unimplemented_handler);

    // STOP should be marked as control flow
    try expect(info_stop.is_control_flow);

    // ADD should not be marked as control flow
    try expect(!info_add.is_control_flow);
}

test "HOMESTEAD adds DELEGATECALL" {
    const frontier_table = InstructionTable.forFork(.FRONTIER);
    const homestead_table = InstructionTable.forFork(.HOMESTEAD);

    const unimplemented_handler = InstructionTable.unimplementedOpcodeHandler;

    // DELEGATECALL (0xF4) should be invalid in FRONTIER
    const frontier_delegatecall = frontier_table.get(0xF4);
    try expect(frontier_delegatecall.handler == unimplemented_handler);

    // DELEGATECALL should be valid in HOMESTEAD
    const homestead_delegatecall = homestead_table.get(0xF4);
    try expect(homestead_delegatecall.handler != unimplemented_handler);
}

test "BYZANTIUM adds REVERT and RETURNDATASIZE" {
    const homestead_table = InstructionTable.forFork(.HOMESTEAD);
    const byzantium_table = InstructionTable.forFork(.BYZANTIUM);

    const unimplemented_handler = InstructionTable.unimplementedOpcodeHandler;

    // RETURNDATASIZE (0x3D) should be invalid in HOMESTEAD
    try expect(homestead_table.get(0x3D).handler == unimplemented_handler);
    // But valid in BYZANTIUM
    try expect(byzantium_table.get(0x3D).handler != unimplemented_handler);

    // REVERT (0xFD) should be invalid in HOMESTEAD
    try expect(homestead_table.get(0xFD).handler == unimplemented_handler);
    // But valid in BYZANTIUM, and marked as control flow
    const revert_info = byzantium_table.get(0xFD);
    try expect(revert_info.handler != unimplemented_handler);
    try expect(revert_info.is_control_flow);
}

test "CONSTANTINOPLE adds shift opcodes" {
    const byzantium_table = InstructionTable.forFork(.BYZANTIUM);
    const constantinople_table = InstructionTable.forFork(.CONSTANTINOPLE);

    const unimplemented_handler = InstructionTable.unimplementedOpcodeHandler;

    // SHL (0x1B) should be invalid in BYZANTIUM
    try expect(byzantium_table.get(0x1B).handler == unimplemented_handler);
    // But valid in CONSTANTINOPLE
    try expect(constantinople_table.get(0x1B).handler != unimplemented_handler);

    // SHR (0x1C) and SAR (0x1D) should also be valid
    try expect(constantinople_table.get(0x1C).handler != unimplemented_handler);
    try expect(constantinople_table.get(0x1D).handler != unimplemented_handler);
}

test "SHANGHAI adds PUSH0" {
    const london_table = InstructionTable.forFork(.LONDON);
    const shanghai_table = InstructionTable.forFork(.SHANGHAI);

    const unimplemented_handler = InstructionTable.unimplementedOpcodeHandler;

    // PUSH0 (0x5F) should be invalid in LONDON
    try expect(london_table.get(0x5F).handler == unimplemented_handler);
    // But valid in SHANGHAI
    try expect(shanghai_table.get(0x5F).handler != unimplemented_handler);
}

test "CANCUN adds MCOPY and blob opcodes" {
    const shanghai_table = InstructionTable.forFork(.SHANGHAI);
    const cancun_table = InstructionTable.forFork(.CANCUN);

    const unimplemented_handler = InstructionTable.unimplementedOpcodeHandler;

    // MCOPY (0x5E) should be invalid in SHANGHAI
    try expect(shanghai_table.get(0x5E).handler == unimplemented_handler);
    // But valid in CANCUN
    const mcopy_info = cancun_table.get(0x5E);
    try expect(mcopy_info.handler != unimplemented_handler);
    // MCOPY should have dynamic gas for memory expansion
    try expect(mcopy_info.dynamic_gas != null);

    // BLOBHASH (0x49) should be valid in CANCUN
    try expect(cancun_table.get(0x49).handler != unimplemented_handler);

    // BLOBBASEFEE (0x4A) should be valid in CANCUN
    try expect(cancun_table.get(0x4A).handler != unimplemented_handler);
}

test "Dynamic gas for memory operations" {
    const table = InstructionTable.forFork(.CANCUN);

    // MLOAD (0x51) should have dynamic gas
    try expect(table.get(0x51).dynamic_gas != null);

    // MSTORE (0x52) should have dynamic gas
    try expect(table.get(0x52).dynamic_gas != null);

    // MSTORE8 (0x53) should have dynamic gas
    try expect(table.get(0x53).dynamic_gas != null);

    // MCOPY (0x5E) should have dynamic gas
    try expect(table.get(0x5E).dynamic_gas != null);

    // RETURN (0xF3) should have dynamic gas
    try expect(table.get(0xF3).dynamic_gas != null);

    // REVERT (0xFD) should have dynamic gas
    try expect(table.get(0xFD).dynamic_gas != null);
}

test "EXP has dynamic gas" {
    const table = InstructionTable.forFork(.FRONTIER);

    // EXP (0x0A) should have dynamic gas for exponent byte length
    const exp_info = table.get(0x0A);
    const unimplemented_handler = InstructionTable.unimplementedOpcodeHandler;
    try expect(exp_info.handler != unimplemented_handler);
    try expect(exp_info.dynamic_gas != null);
}

--[[
-- Decoding for MIPS opcodes.
--
-- The decoder takes a PC and a function to read data and produces a function to interpret the instructions until a
-- branch. The secret to this trick is that it produces a linear and hopefully frequently executed trace to be JITted.
--
-- I stole this approach of table of tables from CEN64, and it works well in LuaJIT because it's branchless.
--]]

local ffi = require("ffi")
local mips = require("chocchip.mips")

local band, bor = bit.band, bit.bor
local lshift, rshift = bit.lshift, bit.rshift

local decode = {}

ffi.cdef[[
    typedef struct DecodeTableEntry {
        // The name of this instruction, which matches the function that should be called.
        char name[32];
        // This instruction could branch, so decoding is stopped after the branch delay slot.
        bool can_branch;
        // This instruction could raise an exception, so a conditional goto is generated.
        bool can_except;
    } DecodeTableEntry;

    typedef struct DecodeTable {
        // Secondary opcode shift.
        uint32_t shift;
        // Secondary opcode mask.
        uint32_t mask;
        // Dispatch table for secondary opcode.
        DecodeTableEntry table[64];
    } DecodeTable;
]]


-- SPECIAL opcodes have an opcode field of zero, and are decoded by their funct field.
-- Most register/register opcodes are in here.
local special_table = ffi.new("DecodeTableEntry[64]", {
    { "sll", false, false },
    { "reserved_instruction", true, true },
    { "srl", false, false },
    { "sra", false, false },
    { "sllv", false, false },
    { "reserved_instruction", true, true },
    { "srlv", false, false },
    { "srav", false, false },
    { "jr", true, false },
    { "jalr", true, false },
    { "movz", false, false },
    { "movn", false, false },
    { "syscall", true, true },
    { "break", true, true },
    { "reserved_instruction", true, true },
    { "sync", false, false },
    { "mfhi", false, false },
    { "mthi", false, false },
    { "mflo", false, false },
    { "mtlo", false, false },
    { "dsllv", false, false },
    { "reserved_instruction", true, true },
    { "dsrlv", false, false },
    { "dsrav", false, false },
    { "mult", false, false },
    { "multu", false, false },
    { "div", false, false },
    { "divu", false, false },
    { "reserved_instruction", true, true }, -- DMULT
    { "reserved_instruction", true, true }, -- DMULTU
    { "reserved_instruction", true, true }, -- DDIV
    { "reserved_instruction", true, true }, -- DDIVU
    { "add", false, true },
    { "addu", false, false },
    { "sub", false, true },
    { "subu", false, false },
    { "band", false, false }, -- AND, but "and" is a reserved keyword
    { "bor", false, false }, -- OR, but "or" is a reserved keyword
    { "xor", false, false },
    { "nor", false, false },
    { "mfsa", false, false },
    { "mtsa", false, false },
    { "slt", false, false },
    { "sltu", false, false },
    { "dadd", false, true },
    { "daddu", false, false },
    { "dsub", false, true },
    { "dsubu", false, false },
    { "tge", true, true },
    { "tgeu", true, true },
    { "tlt", true, true },
    { "tltu", true, true },
    { "teq", true, true },
    { "reserved_instruction", true, true },
    { "tne", true, true },
    { "reserved_instruction", true, true },
    { "dsll", false, false },
    { "reserved_instruction", true, true },
    { "dsrl", false, false },
    { "dsra", false, false },
    { "dsll32", false, false },
    { "reserved_instruction", true, true },
    { "dsrl32", false, false },
    { "dsra32", false, false },
})

-- REGIMM opcodes have an opcode field of one and are decoded by their rt field.
-- Instructions that take a 16-bit immediate go here.
local regimm_table = ffi.new("DecodeTableEntry[64]", {
    { "bltz", true, true },
    { "bgez", true, false },
    { "bltzl", true, true },
    { "bgezl", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "tgei", true, true },
    { "tgeiu", true, true },
    { "tlti", true, true },
    { "tltiu", true, true },
    { "teqi", true, true },
    { "reserved_instruction", true, true },
    { "tnei", true, true },
    { "reserved_instruction", true, true },
    { "bltzal", true, true },
    { "bgezal", true, true },
    { "bltzall", true, true },
    { "bgezall", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "mtsab", false, true },
    { "mtsah", false, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
})

-- COP0 opcodes have an opcode field of sixteen and are decoded by their rs field...Sometimes.
-- Some opcodes are further decoded by their rt fields, making them triply indirect; we handle them specially.
local cop0_table = ffi.new("DecodeTableEntry[64]", {
    { "mfc0", false, false }, -- TODO: can_except should be true, because this can raise CpU in user mode.
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "mtc0", false, false }, -- TODO: can_except should be true, because this can raise CpU in user mode.
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "bc0", true, false }, -- TODO: can_except should be true, because this can raise CpU in user mode.
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "c0", false, false }, -- TODO: can_except should be true, because this can raise CpU in user mode.
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
    { "reserved_instruction", true, true },
})

-- All other MIPS opcodes go here.
local general_table = ffi.new("DecodeTableEntry[64]", {
    { "special_decode_bug", true, true }, -- SPECIAL, hopefully unreachable.
    { "regimm_decode_bug", true, true }, -- REGIMM, hopefully unreachable.
    { "j", true, false },
    { "jal", true, false },
    { "beq", true, false },
    { "bne", true, false },
    { "blez", true, false },
    { "bgtz", true, false },
    { "addi", false, true },
    { "addiu", false, false },
    { "slti", false, false },
    { "sltiu", false, false },
    { "bandi", false, false }, -- ANDI, but "and" is a Lua reserved keyword.
    { "bori", false, false },
    { "xori", false, false },
    { "lui", false, false },
    { "cop0_decode_bug", true, true }, -- COP0, hopefully unreachable.
    { "cop1_decode_bug", true, true }, -- COP1, hopefully unreachable.
    { "cop2_decode_bug", true, true }, -- COP2, hopefully unreachable.
    { "cop3_decode_bug", true, true }, -- COP3 was removed in MIPS III.
    { "beql", true, true },
    { "bnel", true, true },
    { "blezl", true, true },
    { "bgtzl", true, true },
    { "daddi", false, true },
    { "daddiu", false, true },
    { "ldl", false, true },
    { "ldr", false, true },
    { "mmi_decode_bug", true, true }, -- MMI, hopefully unreachable.
    { "reserved_instruction", true, true },
    { "lq", false, true },
    { "sq", false, true },
    { "lb", false, true },
    { "lh", false, true },
    { "lwl", false, true },
    { "lw", false, false }, -- TODO: Change can_except to true because of MMU failure.
    { "lbu", false, false }, -- TODO: Change can_except to true because of MMU failure.
    { "lhu", false, false }, -- TODO: Change can_except to true because of MMU failure.
    { "lwr", false, true },
    { "lwu", false, true },
    { "sb", false, true },
    { "sh", false, false }, -- TODO: Change can_except to true because of MMU failure.
    { "swl", false, true },
    { "sw", false, false }, -- TODO: Change can_except to true because of MMU failure.
    { "sdl", false, true },
    { "sdr", false, true },
    { "swr", false, true },
    { "cache", false, true }, -- Should this be treated as a branch because of icache flushing?
    { "reserved_instruction", true, true }, -- LL
    { "lwc1", false, true },
    { "reserved_instruction", true, true }, -- LWC2
    { "pref", false, true }, -- LWC3, removed in MIPS III, replaced with PREF in MIPS IV
    { "reserved_instruction", true, true }, -- LLD
    { "reserved_instruction", true, true }, -- LDC1
    { "lqc2", false, true },
    { "ld", false, true },
    { "reserved_instruction", true, true }, -- SC
    { "swc1", false, true },
    { "reserved_instruction", true, true }, -- SWC2
    { "reserved_instruction", true, true }, -- SWC3, removed in MIPS III
    { "reserved_instruction", true, true }, -- SCD
    { "reserved_instruction", true, true }, -- SDC1
    { "sqc1", false, true },
    { "sd", false, false }, -- TODO: Change can_except to true because of MMU failure.
})

-- A table of tables to decode MIPS instructions from the opcode field.
local decode_table = ffi.new("DecodeTable[64]", {
    { 0, 0x3F, special_table },
    { 16, 0x1F, regimm_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 21, 0x1F, cop0_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
})

function decode.decode(read4, pc)
    assert(type(read4) == "function", "read4 is not a function")
    assert(type(pc) == "number", "pc is not a number")

    local stop_decoding = false
    local branch_delay_slot = false
    local ops = {"local interpret = require(\"chocchip.r5900.interpret\")\n local s = _G[\"s\"]"}
    local op_count = 0

    while stop_decoding == false do
        local insn = read4(pc)

        local insn_op = mips.opcode_field(insn)
        local insn_rs = mips.first_source_reg(insn)
        local insn_rt = mips.second_source_reg(insn)
        local insn_rd = mips.destination_reg(insn)
        local insn_shamt = mips.shift_amount(insn)
        local insn_funct = mips.funct_field(insn)

        local entry = decode_table[mips.opcode_field(insn)]
        local opcode = band(rshift(insn, entry.shift), entry.mask)
        local op = ffi.string(entry.table[opcode].name)
        op = table.concat({
            "\ns:",
            op,
            "(",
            insn_op,
            ", ",
            insn_rs,
            ", ",
            insn_rt,
            ", ",
            insn_rd,
            ", ",
            insn_shamt,
            ", ",
            insn_funct,
            "); s:cycle_update()"
        })

        stop_decoding = entry.table[opcode].can_except or branch_delay_slot
        branch_delay_slot = entry.table[opcode].can_branch

        if entry.table[opcode].can_except then
            io.write(ffi.string(entry.table[opcode].name), " can raise exception; finishing trace")
        end
        --io.write(bit.tohex(pc), " ", bit.tohex(insn), ": ", op, "\n")

        ops[#ops+1] = op
        pc = pc + 4
        op_count = op_count + 1
    end

    return table.concat(ops), op_count
end

return decode

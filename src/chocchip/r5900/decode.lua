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
        DecodeTableEntry* table;
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
    { "and", false, false },
    { "or", false, false },
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
    { "bgez", true, true },
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

local cop0_table = ffi.new("DecodeTableEntry[32]", {
    { "mfc0", false, false },
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
    { "reserved_instruction", true, true },
})

-- All other MIPS opcodes go here.
local general_table = ffi.new("DecodeTableEntry[64]", {
    { "special_decode_bug", true, true }, -- SPECIAL, hopefully unreachable.
    { "regimm_decode_bug", true, true }, -- REGIMM, hopefully unreachable.
    { "j", true, true },
    { "jalr", true, true },
    { "beq", true, true },
    { "bne", true, true },
    { "blez", true, true },
    { "bgtz", true, true },
    { "addi", false, true },
    { "addiu", false, true },
    { "slti", false, true },
    { "sltiu", false, true },
    { "andi", false, true },
    { "ori", false, true },
    { "xori", false, true },
    { "lui", false, true },
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
    { "lw", false, true },
    { "lbu", false, true },
    { "lhu", false, true },
    { "lwr", false, true },
    { "lwu", false, true },
    { "sb", false, true },
    { "sh", false, true },
    { "swl", false, true },
    { "sw", false, true },
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
    { "sd", false, true },
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

function decode.decode(self, read_byte, pc)
    local stop_decoding = false
    local ops = {}

    while stop_decoding == false do
        local insn = bor(
            read_byte(self, pc),
            lshift(read_byte(self, pc + 1), 8),
            lshift(read_byte(self, pc + 2), 16),
            lshift(read_byte(self, pc + 3), 24))

        local entry = decode_table[mips.opcode_field(insn)]
        local opcode = band(rshift(insn, entry.shift), entry.mask) + 1
        local op = ffi.string(entry.table[opcode].name)
        stop_decoding = entry.table[opcode].can_branch or entry.table[opcode].can_except

        io.write(bit.tohex(pc), " ", bit.tohex(insn), ": ", op, "\n")

        ops[#ops+1] = op
        pc = pc + 4
    end

    return table.concat(ops)
end

return decode

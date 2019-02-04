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

local band = bit.band
local lshift, rshift = bit.lshift, bit.rshift

local decode = {}

ffi.cdef[[
    typedef struct DecodeTableEntry {
        char name[20];
        bool branches;
    } DecodeTableEntry;

    typedef struct DecodeTable {
        uint32_t shift;
        uint32_t mask;
        DecodeTableEntry* table;
    } DecodeTable;
]]


-- SPECIAL opcodes have an opcode field of zero, and are decoded by their funct field.
-- Most register/register opcodes are in here.
local special_table = ffi.new("DecodeTableEntry[64]", {
    { "sll", false },
    { "reserved_instruction", true },
    { "srl", false },
    { "sra", false },
    { "sllv", false },
    { "reserved_instruction", true },
    { "srlv", false },
    { "srav", false },
    { "jr", true },
    { "jalr", true },
    { "movz", false },
    { "movn", false },
    { "syscall", true },
    { "break", true },
    { "reserved_instruction", true },
    { "sync", false },
    { "mfhi", false },
    { "mthi", false },
    { "mflo", false },
    { "mtlo", false },
    { "dsllv", false },
    { "reserved_instruction", true },
    { "dsrlv", false },
    { "dsrav", false },
    { "mult", false },
    { "multu", false },
    { "div", false },
    { "divu", false },
    { "reserved_instruction", true }, -- DMULT
    { "reserved_instruction", true }, -- DMULTU
    { "reserved_instruction", true }, -- DDIV
    { "reserved_instruction", true }, -- DDIVU
    { "add", false },
    { "addu", false },
    { "sub", false },
    { "subu", false },
    { "and", false },
    { "or", false },
    { "xor", false },
    { "nor", false },
    { "mfsa", false },
    { "mtsa", false },
    { "slt", false },
    { "sltu", false },
    { "dadd", false },
    { "daddu", false },
    { "dsub", false },
    { "dsubu", false },
    { "tge", true },
    { "tgeu", true },
    { "tlt", true },
    { "tltu", true },
    { "teq", true },
    { "reserved_instruction", true },
    { "tne", true },
    { "reserved_instruction", true },
    { "dsll", false },
    { "reserved_instruction", true },
    { "dsrl", false },
    { "dsra", false },
    { "dsll32", false },
    { "reserved_instruction", true },
    { "dsrl32", false },
    { "dsra32", false },
})

-- REGIMM opcodes have an opcode field of one and are decoded by their rt field.
-- Instructions that take a 16-bit immediate go here.
local regimm_table = ffi.new("DecodeTableEntry[64]", {
    { "bltz", true },
    { "bgez", true },
    { "bltzl", true },
    { "bgezl", true },
    { "reserved_instruction", true },
    { "reserved_instruction", true },
    { "reserved_instruction", true },
    { "reserved_instruction", true },
    { "tgei", true },
    { "tgeiu", true },
    { "tlti", true },
    { "tltiu", true },
    { "teqi", true },
    { "reserved_instruction", true },
    { "tnei", true },
    { "reserved_instruction", true },
    { "bltzal", true },
    { "bgezal", true },
    { "bltzall", true },
    { "bgezall", true },
    { "reserved_instruction", true },
    { "reserved_instruction", true },
    { "reserved_instruction", true },
    { "reserved_instruction", true },
    { "mtsab", false },
    { "mtsah", false },
    { "reserved_instruction", true },
    { "reserved_instruction", true },
    { "reserved_instruction", true },
    { "reserved_instruction", true },
    { "reserved_instruction", true },
    { "reserved_instruction", true },
})

local cop0_table = ffi.new("DecodeTableEntry[32]")

-- All other MIPS opcodes go here.
local general_table = ffi.new("DecodeTableEntry[64]", {
    { "special_decode_bug", true }, -- SPECIAL, hopefully unreachable.
    { "regimm_decode_bug", true }, -- REGIMM, hopefully unreachable.
    { "j", true },
    { "jalr", true },
    { "beq", true },
    { "bne", true },
    { "blez", true },
    { "bgtz", true },
    { "addi", false },
    { "addiu", false },
    { "slti", false },
    { "sltiu", false },
    { "andi", false },
    { "ori", false },
    { "xori", false },
    { "lui", false },
    { "cop0_decode_bug", true }, -- COP0, hopefully unreachable.
    { "cop1_decode_bug", true }, -- COP1, hopefully unreachable.
    { "cop2_decode_bug", true }, -- COP2, hopefully unreachable.
    { "cop3_decode_bug", true }, -- COP3 was removed in MIPS III.
    { "beql", true },
    { "bnel", true },
    { "blezl", true },
    { "bgtzl", true },
    { "daddi", false },
    { "daddiu", false },
    { "ldl", false },
    { "ldr", false },
    { "mmi_decode_bug", true }, -- MMI, hopefully unreachable.
    { "reserved_instruction", true },
    { "lq", false },
    { "sq", false },
    { "lb", false },
    { "lh", false },
    { "lwl", false },
    { "lw", false },
    { "lbu", false },
    { "lhu", false },
    { "lwr", false },
    { "lwu", false },
    { "sb", false },
    { "sh", false },
    { "swl", false },
    { "sw", false },
    { "sdl", false },
    { "sdr", false },
    { "swr", false },
    { "cache", false }, -- Should this be treated as a branch because of icache flushing?
    { "reserved_instruction", true }, -- LL
    { "lwc1", false },
    { "reserved_instruction", true }, -- LWC2
    { "pref", false }, -- LWC3, removed in MIPS III, replaced with PREF in MIPS IV
    { "reserved_instruction", true }, -- LLD
    { "reserved_instruction", true }, -- LDC1
    { "lqc2", false },
    { "ld", false },
    { "reserved_instruction", true }, -- SC
    { "swc1", false },
    { "reserved_instruction", true }, -- SWC2
    { "reserved_instruction", true }, -- SWC3, removed in MIPS III
    { "reserved_instruction", true }, -- SCD
    { "reserved_instruction", true }, -- SDC1
    { "sqc1", false },
    { "sd", false },
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
    { 26, 0x3F, general_table },
})

function decode.decode(read_byte, pc)
    local stop_decoding = false
    local ops = {}

    --while stop_decoding == false do
        --[[local insn = bor(
            read_byte(pc),
            lshift(read_byte(pc + 1), 8),
            lshift(read_byte(pc + 2), 16),
            lshift(read_byte(pc + 3), 24))]]
        --local insn - read_byte
        --local insn = bor(lshift(1, 26), lshift(read_byte, 16))
        local insn = lshift(read_byte, 26)

        local entry = decode_table[mips.opcode_field(insn)]
        local opcode = band(rshift(insn, entry.shift), entry.mask)
        local op = entry.table[opcode].name

        --ops[#ops+1] = op
    --    break
    --end

    return tostring(op) --table.concat(ops,"")
end

for i=0,1023 do
    decode.decode(band(i, 63), 0)
end

return decode

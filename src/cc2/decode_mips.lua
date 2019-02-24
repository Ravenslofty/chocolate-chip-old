local bit = require("bit")
local ffi = require("ffi")

local istype = ffi.istype

local band = bit.band
local rshift = bit.rshift

local mips_decode = {}

local instance = {
    decode_table = nil
}

local function opcode(instruction)
    return band(rshift(instruction, 26), 0x3F)
end

local function first_source(instruction)
    return band(rshift(instruction, 26), 0x3F)
end

local function second_source(instruction)
    return band(rshift(instruction, 26), 0x3F)
end

local function destination(instruction)
    return band(rshift(instruction, 26), 0x3F)
end

local function shift_amount(instruction)
    return band(rshift(instruction, 26), 0x3F)
end

local function function_field(instruction)
    return band(rshift(instruction, 26), 0x3F)
end

function instance:decode_instruction(instruction)
    local opcode = opcode(instruction)
    local first_source = first_source(instruction)
    local second_source = second_source(instruction)
    local destination = destination(instruction)
    local shift_amount = shift_amount(instruction)
    local function_field = function_field(instruction)

    local opcode1 = self.decode_table[opcode + 1]

    local shift = opcode1[1]
    local mask = opcode1[2]
    local table = opcode1[3]

    print(opcode, opcode1, shift, mask, table)
    
    local index = band(rshift(instruction, shift), mask)
    local handler = table[index + 1]

    return handler(self, opcode, first_source, second_source, destination, shift_amount, function_field)
end

function instance:decode(read32, program_counter)
    local keep_decoding = true
    local ops = {}

    while keep_decoding do
        local instruction = read32(program_counter)
        local decode_ok, op, branch_target, likely_branch = self:decode_instruction(instruction)
        keep_decoding = decode_ok
        
        ops[#ops+1] = op

        program_counter = program_counter + 4
    end

    return table.concat(ops)
end 

local DecodeInstance = {__index = instance}

function mips_decode:new(decode_table)
    return setmetatable({
        decode_table = decode_table,
        gpr_declared = {},
        gpr_needs_writeback = {},
        cp0r_declared = {},
        cp0r_needs_writeback = {}
    },
    DecodeInstance)
end

local names = {
    "zero",
    "at",
    "v0",
    "v1",
    "a0",
    "a1",
    "a2",
    "a3",
    "t0",
    "t1",
    "t2",
    "t3",
    "t4",
    "t5",
    "t6",
    "t7",
    "s0",
    "s1",
    "s2",
    "s3",
    "s4",
    "s5",
    "s6",
    "s7",
    "t8",
    "t9",
    "k0",
    "k1",
    "gp",
    "sp",
    "fp",
    "ra"
}

function mips_decode.register_name(register)
    return names[register]
end

return mips_decode

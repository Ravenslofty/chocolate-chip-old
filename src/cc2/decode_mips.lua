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
    return band(rshift(instruction, 21), 0x1F)
end

local function second_source(instruction)
    return band(rshift(instruction, 16), 0x1F)
end

local function destination(instruction)
    return band(rshift(instruction, 11), 0x1F)
end

local function shift_amount(instruction)
    return band(rshift(instruction, 6), 0x1F)
end

local function function_field(instruction)
    return band(rshift(instruction, 0), 0x3F)
end

function instance:decode_instruction(instruction)
    if instruction == 0 then
        return true, ""
    end

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

function instance:decode(read32)
    local keep_decoding = true
    local branch_delay = false
    local next_address = ""
    local ops = {}

    while keep_decoding do
        local instruction = read32(self.program_counter)
        local decode_ok, op, branch_target, likely_branch = self:decode_instruction(instruction)
        keep_decoding = decode_ok and not branch_delay
        branch_delay = (branch_target ~= nil)
        likely_branch = likely_branch ~= nil and likely_branch

        if likely_branch then
            assert(branch_delay, "likely branch outside of branch delay slot")
            ops[#ops+1] = "if branch_condition then\n"
        end

        ops[#ops+1] = op

        if likely_branch then
            ops[#ops+1] = "end\n"
        end

        if branch_target ~= nil then
            next_address = branch_target
        end

        self.program_counter = self.program_counter + 4
    end

    ops[#ops+1] = self:write_back_registers()
    --
    -- Return via tail call.
    assert(next_address ~= "")
    ops[#ops+1] = table.concat({
        "if branch_condition then\n",
        "\treturn run[",
        next_address,
        "]()\n",
        "else\n",
        "\treturn run[0x",
        bit.tohex(self.program_counter),
        "]()\n",
        "end\n"
    })

    return table.concat(ops)
end 

local DecodeInstance = {__index = instance}

function mips_decode.new(decode_table, program_counter)
    assert(type(decode_table) == "table", "decode_table is not a table")
    assert(tonumber(program_counter), "program_counter is not convertible to number")

    local instance = {
        decode_table = decode_table,
        gpr_declared = {},
        gpr_needs_writeback = {},
        cp0r_declared = {},
        cp0r_needs_writeback = {},
        program_counter = tonumber(program_counter)
    }

    for i=0,31 do
        instance.gpr_declared[i] = false
        instance.gpr_needs_writeback[i] = false
        instance.cp0r_declared[i] = false
        instance.cp0r_needs_writeback[i] = false
    end

    return setmetatable(instance, DecodeInstance)
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
    assert(tonumber(register))
    return names[register + 1]
end

return mips_decode

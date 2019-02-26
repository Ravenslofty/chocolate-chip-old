local mips = require("cc2.decode_mips")
local util = require("cc2.r5900.decode_util")

local general_table = require("cc2.r5900.decode_general")
local special_table = require("cc2.r5900.decode_special")
local regimm_table = require("cc2.r5900.decode_regimm")
local cop0_table = require("cc2.r5900.decode_cop0")

local decode = {}

local decode_table = {
    { 0, 0x3F, special_table },
    { 16, 0x1F, regimm_table },
    {},
    {},
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    {},
    {},
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 21, 0x1F, cop0_table },
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
}

local function write_back_registers(self)
    local ops = {}

    -- Write back GPRs.
    for gpr=0,31 do
        if self.gpr_needs_writeback[gpr] then
            ops[#ops+1] = table.concat({
                "s.gpr[",
                gpr,
                "] = ",
                mips.register_name(gpr),
                "\n"
            })
        end
    end

    -- Write back COP0 registers.
    for cp0r=0,31 do
        if self.cp0r_needs_writeback[cp0r] then
            ops[#ops+1] = table.concat({
                "s.cp0r[",
                cp0r,
                "] = ",
                util.cop0_register_name(gpr),
                "\n"
            })
        end
    end

    return table.concat(ops)
end

function decode.new(program_counter)
    assert(tonumber(program_counter), "program_counter is not convertible to number")
    local decoder = mips.new(decode_table, program_counter)
    decoder.write_back_registers = write_back_registers
    return decoder
end

return decode

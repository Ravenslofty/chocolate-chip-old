local mips = require("cc2.decode_mips")
local util = require("cc2.r5900.decode_util")

local function move_from_cop0(self, _, _, destination, source, _, _)
    local op = {
        -- Operands
        util.declare_cop0_source(self, source),
        util.declare_destination(self, destination),
        -- Assign
        util.cop0_register_name(source),
    }

    return true, table.concat(op)
end

local function move_to_cop0(self, _, _, source, destination, _, _)
    local op = {
        -- Operands
        util.declare_source(self, source),
        util.declare_cop0_destination(self, destination),
        -- Assign
        mips:register_name(source),
    }

    return true, table.concat(op)
end

local cop0_table = {
    move_from_cop0,             -- MFC0
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction,
    move_to_cop0,               -- MTC0
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction,
    {},                         -- BC0
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction,
    {},                         -- C0
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction
}

return cop0_table

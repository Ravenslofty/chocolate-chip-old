local bit = require("bit")

local util = require("cc2.r5900.decode_util")

local function branch_target_address(self, target3, target2, target1)
    local addr = bit.bor(bit.lshift(target3, 11), bit.lshift(target2, 6), target1)
    addr = bit.arshift(bit.lshift(addr, 16), 14) -- Sign extend from 16 to 18 bits.
    return addr + self.pc
end

local function compare_and_branch(self, _, first_source, opcode, target3, target2, target1)
    -- The 0x01 bit inverts the comparison. In this case, the only possible comparisons are >= 0 or < 0.
    local operation = bit.band(opcode, 0x01) and " >= 0\n" or " < 0\n"

    -- The 0x02 bit signifies that the branch delay slot has no effect if the branch condition is false.
    local likely_branch = bit.band(opcode, 0x02) ~= 0

    -- The 0x10 bit signifies that the return address register is updated to the instruction after the 
    -- branch delay slot.
    local linked_branch = bit.band(opcode, 0x10) ~= 0

    first_source = mips.register_name(second_source)

    local op = {
        -- Operands
        self:declare_source(first_source),
        -- Compare
        "local branch_condition = ",
        first_source,
        operation,
    }

    if linked_branch then
        op[#op + 1] = table.concat({
            self:declare_destination("ra"),
            tostring(self.pc + 8)
        })
    end

    local addr = branch_target_address(self, target3, target2, target1)

    return true, table.concat(op), addr, likely_branch
end

local function conditional_trap(self, _, source, opcode, imm3, imm2, imm1)
    -- The 0x01 bit specifies whether to perform signed or unsigned comparison.
    local comparison_is_unsigned = bit.band(function_field, 0x01) ~= 0

    -- The 0x02 bit specifies whether to invert the comparison result.
    -- This turns a greater-than-or-equal comparison to a less-than comparison, 
    -- and an equality test to an inequality test.
    local invert_comparison = bit.band(function_field, 0x02) ~= 0

    -- The 0x04 bit specifies whether to use greater-than-or-equal comparison or an equality test.
    local comparison_is_equality = bit.band(function_field, 0x04) ~= 0

    assert(not(comparison_is_equality and comparison_is_unsigned), "reserved instruction: trap on unsigned (in)equality to immediate")

    local imm = bit.bor(bit.lshift(imm3, 11), bit.lshift(imm2, 6), imm1)

    local compare_type = comparison_is_unsigned and "uint64_t" or "int64_t"
    local invert = invert_comparison and "not" or ""
    local operation = comparison_is_equality and "==" or ">="

    source = mips.register_name(first_source)

    local op = {
        -- Operands
        self:declare_source(source),
        -- Operate
        "assert(",
        invert,
        "(ffi.cast(\"",
        compare_type,
        "\", ",
        source,
        ") ",
        operation,
        " ",
        tostring(ffi.cast(compare_type, imm))
        ")) ,\"conditional trap\")\n"
    }

    return true, table.concat(op)
end

local regimm_table = {
    compare_and_branch, -- BLTZ
    compare_and_branch, -- BGEZ
    compare_and_branch, -- BLTZL
    compare_and_branch, -- BGEZL
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction,
    conditional_trap,   -- TGEI
    conditional_trap,   -- TGEIU
    conditional_trap,   -- TLTI
    conditional_trap,   -- TLTIU
    conditional_trap,   -- TEQI
    conditional_trap,
    conditional_trap,   -- TNEI
    conditional_trap,
    compare_and_branch, -- BLTZAL
    compare_and_branch, -- BGEZAL
    compare_and_branch, -- BLTZALL
    compare_and_branch, -- BGEZALL
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction,
    {},                 -- MTSAB
    {},                 -- MTSAH
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction,
}

return regimm_table

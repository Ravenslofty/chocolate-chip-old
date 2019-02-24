local bit = require("bit")

local util = require("cc2.r5900.decode_util")

local function add_constant(self, opcode, source, destination, imm3, imm2, imm1)
    -- The 0x01 bit signifies whether to perform overflow checks on the result.
    local op_is_signed = bit.band(opcode, 0x01) == 0

    -- The 0x08 bit signifies that the operation is 64-bit, and doesn't need to be sign-extended.
    local op_is_64bit = bit.band(opcode, 0x04) ~= 0

    local imm = util.construct_immediate(imm3, imm2, imm1)

    local op = {
        -- Operands
        util.declare_source(self, source),
        -- Operate
        util.declare_destination(self, destination),
        source,
        " + ",
        tostring(imm),
        "\n"
    }

    if op_is_signed then
        -- TODO: Overflow checking.
    end

    if not op_is_64bit then
        op[#op + 1] = util.sign_extend_32_64(destination)
    end

    return true, table.concat(op)
end

local function set_if_less_than(self, opcode, source, destination, imm3, imm2, imm1)
    -- The 0x01 bit specifies whether to perform signed or unsigned comparison.
    local comparison_is_unsigned = bit.band(opcode, 0x01) ~= 0

    local compare_type = comparison_is_unsigned and "uint64_t" or "int64_t"
    local imm = util.construct_immediate(imm3, imm2, imm1)

    local op = {
        -- Operands
        util.declare_source(self, source),
        util.declare_destination(self, destination), 
        -- Operate
        "(ffi.cast(\"",
        compare_type,
        "\", ",
        source,
        ") < ffi.cast(\"",
        compare_type,
        "\", ",
        tostring(imm),
        ") and 1 or 0\n",
    }

    return table.concat(op), true
end

local general_table = {
    {},                 -- [SPECIAL]
    {},                 -- [REGIMM]
    {},                 -- J
    {},                 -- JAL
    {},                 -- BEQ
    {},                 -- BNE
    {},                 -- BLEZ
    {},                 -- BGTZ
    add_constant,       -- ADDI
    add_constant,       -- ADDIU
    set_if_less_than,   -- SLTI
    set_if_less_than,   -- SLTIU
    {},                 -- ANDI
    {},                 -- ORI
    {},                 -- XORI
    {},                 -- LUI
    {},                 -- [COP0]
    {},                 -- [COP1]
    {},                 -- [COP2]
    util.illegal_instruction,
    {},                 -- BEQL
    {},                 -- BNEL
    {},                 -- BLEZL
    {},                 -- BGTZL
    add_constant,       -- DADDI
    add_constant,       -- DADDIU
    {},                 -- LDL
    {},                 -- LDR
    {},                 -- [MMI]
    util.illegal_instruction,
    {},                 -- LQ
    {},                 -- SQ
    {},                 -- LB
    {},                 -- LH
    {},                 -- LWL
    {},                 -- LW
    {},                 -- LBU
    {},                 -- LHU
    {},                 -- LWR
    {},                 -- LWU
    {},                 -- SB
    {},                 -- SH
    {},                 -- SWL
    {},                 -- SW
    {},                 -- SDL
    {},                 -- SDR
    {},                 -- SWR
    {},                 -- CACHE
    util.illegal_instruction,
    {},                 -- LWC1
    util.illegal_instruction,
    {},                 -- PREF
    util.illegal_instruction,
    util.illegal_instruction,
    {},                 -- LQC2
    {},                 -- LD
    util.illegal_instruction,
    {},                 -- SWC1
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction,
    util.illegal_instruction,
    {},                 -- SQC2
    {}                  -- SD
}

return general_table


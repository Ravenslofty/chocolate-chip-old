local bit = require("bit")

local mips = require("cc2.decode_mips")
local util = require("cc2.r5900.decode_util")

local function equality_branch(self, opcode, first_source, second_source, target3, target2, target1)
    -- The 0x01 bit inverts the check. 
    local invert_comparison = bit.band(opcode, 0x01) ~= 0

    -- The 0x10 bit signifies that the branch delay slot has no effect if the branch condition is false.
    local likely_branch = bit.band(opcode, 0x10) ~= 0

    local operation = invert_comparison and " ~= " or " == "

    local op = {
        -- Operands
        util.declare_source(self, first_source),
        util.declare_source(self, second_source),
        -- Compare
        "local branch_condition = (",
        mips.register_name(first_source),
        operation,
        mips.register_name(second_source),
        ")\n"
    }

    local addr = util.branch_target_address(self, target3, target2, target1)

    return true, table.concat(op), "0x" .. bit.tohex(addr), likely_branch
end

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
        mips.register_name(source),
        " + 0x",
        bit.tohex(imm),
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
        mips.register_name(source),
        ") < ffi.cast(\"",
        compare_type,
        "\", 0x",
        bit.tohex(imm),
        ")) and 1 or 0\n",
    }

    return true, table.concat(op)
end

local function bitop_constant(self, opcode, source, destination, imm3, imm2, imm1)
    -- Haven't found a way to break the instruction encoding down; the instruction encoding probably
    -- selects a logical function unit inside the ALU.

    local op_table = {
        [0x0C] = "band",    -- ANDI
        [0x0D] = "bor",     -- ORI
        [0x0E] = "bxor",    -- XORI
    }

    local imm = util.construct_immediate(imm3, imm2, imm1)

    local op = {
        -- Operands
        util.declare_source(self, source),
        -- Operate
        util.declare_destination(self, destination),
        op_table[opcode],
        "(",
        mips.register_name(source),
        ", 0x",
        bit.tohex(imm),
        ")\n"
    }

    return true, table.concat(op)
end

local function load_upper(self, _, _, destination, imm3, imm2, imm1)
    local imm = util.construct_immediate(imm3, imm2, imm1)
    imm = bit.arshift(bit.lshift(imm, 48), 32)

    local op = {
        -- Operands
        util.declare_destination(self, destination),
        -- Operate
        "0x",
        bit.tohex(imm),
        "LL\n"
    }

    return true, table.concat(op)
end
local general_table = {
    {},                 -- [SPECIAL]
    {},                 -- [REGIMM]
    {},                 -- J
    {},                 -- JAL
    equality_branch,    -- BEQ
    equality_branch,    -- BNE
    {},                 -- BLEZ
    {},                 -- BGTZ
    add_constant,       -- ADDI
    add_constant,       -- ADDIU
    set_if_less_than,   -- SLTI
    set_if_less_than,   -- SLTIU
    bitop_constant,     -- ANDI
    bitop_constant,     -- ORI
    bitop_constant,     -- XORI
    load_upper,         -- LUI
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


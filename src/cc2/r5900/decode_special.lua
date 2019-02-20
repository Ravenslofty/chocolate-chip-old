local function shift_immediate(self, _, _, second_source, destination, shift_amount, function_field)
    -- The 0x01 bit signifies an arithmetic shift, which shifts in the sign-bit instead of zeroes.
    local arithmetic_shift = bit.band(function_field, 0x01) ~= 0
    
    -- The 0x02 bit signifies a right shift, equivalent to a division by two.
    local right_shift = bit.band(function_field, 0x02) ~= 0

    -- The 0x04 bit signifies that 32 needs to be added to shift_amount in 64-bit shift.
    local needs_shift_offset = bit.band(function_field, 0x04) ~= 0

    -- The 0x08 bit signifies that the operation is 64-bit, and doesn't need to be sign-extended.
    local shift_is_64bit = bit.band(function_field, 0x10) ~= 0
    
    assert(not(arithmetic_shift and not needs_shift_offset), "reserved instruction: arithmetic left shift")
    assert(not(needs_shift_offset and not shift_is_64bit), "reserved instruction: 32-bit shift with 32-bit shift offset")

    local operation = table.concat({
        arithmetic_shift and "a" or "",
        right_shift and "r" or "l",
        "shift"
    })

    -- -32 instructions use shift_amount + 32
    local shift_base = needs_shift_offset and 32 or 0

    second_source = mips.register_name(second_source)
    destination = mips.register_name(destination)

    local op = {
        -- Operands
        self:declare_source(second_source),
        -- Shift
        self:declare_destination(destination),
        operation,
        "(",
        second_source,
        ", ",
        tostring(shift_amount + shift_base),
        ")\n",
    }

    if not shift_is_64bit then
        op[#op + 1] = util.sign_extend_32_64(destination)
    end

    return true, table.concat(op)
end

local function shift_variable(self, _, first_source, second_source, destination, _, function_field)
    -- The 0x01 bit signifies an arithmetic shift, which shifts in the sign-bit instead of zeroes.
    local arithmetic_shift = bit.band(function_field, 0x01) ~= 0
    
    -- The 0x02 bit signifies a right shift, equivalent to a division by two.
    local right_shift = bit.band(function_field, 0x02) ~= 0

    -- The 0x10 bit signifies that the operation is 64-bit, and doesn't need to be sign-extended.
    local shift_is_64bit = bit.band(function_field, 0x10) ~= 0
    
    local operation = table.concat({
        arithmetic_shift and "a" or "",
        right_shift and "r" or "l",
        "shift"
    })

    -- 32-bit instructions use the low 5 bits, 64-bit instructions use the low 6 bits.
    local mask = shift_is_64bit and 0x3F or 0x1F

    first_source = mips.register_name(first_source)
    second_source = mips.register_name(second_source)
    destination = mips.register_name(destination)

    local op = {
        -- Operands
        self:declare_source(first_source),
        self:declare_source(second_source),
        self:declare_destination(destination),
        -- Shift
        op_table[function_field],
        "(",
        second_source,
        ", band(",
        first_source,
        ",",
        tostring(mask),
        "))\n",
    }

    if not shift_is_64bit then
        op[#op + 1] = util.sign_extend_32_64(destination)
    end

    return true, table.concat(op)
end

local function bitop_register(self, _, first_source, second_source, destination, _, function_field)
    -- Haven't found a way to break the instruction encoding down; the instruction encoding probably
    -- selects a logical function unit inside the ALU.

    local op_table = {
        [0x24] = "band",     -- AND
        [0x25] = "bor",      -- OR
        [0x26] = "bxor",     -- XOR
        [0x27] = "bnot(bor(" -- NOR
    }

    local end_bracket = {
        [0x24] = "", -- AND
        [0x25] = "", -- OR
        [0x26] = "", -- XOR
        [0x27] = ")" -- NOR
    }

    first_source = mips.register_name(first_source)
    second_source = mips.register_name(second_source)
    destination = mips.register_name(destination)

    local op = {
        -- Operands
        self:declare_source(first_source),
        self:declare_source(second_source),
        -- Operate
        self:declare_destination(destination),
        op_table[function_field],
        "(",
        first_source,
        ", ",
        second_source,
        ")",
        end_bracket[function_field],
        "\n"
    }

    return true, table.concat(op)
end

local function addsub_register(self, _, first_source, second_source, destination, _, function_field)
    -- The 0x01 bit signifies whether to perform overflow checks on the result.
    local op_is_signed = bit.band(function_field, 0x01) == 0

    -- The 0x02 bit signifies whether to perform addition or subtraction.
    local op_is_subtraction = bit.band(function_field, 0x02) ~= 0

    -- The 0x04 bit signifies that the operation is 64-bit, and doesn't need to be sign-extended.
    local op_is_64bit = bit.band(function_field, 0x04) ~= 0

    local operation = op_is_subtraction and "-" or "+"

    first_source = mips.register_name(first_source)
    second_source = mips.register_name(second_source)
    destination = mips.register_name(destination)

    local op = {
        -- Operands
        self:declare_source(first_source),
        self:declare_source(second_source),
        -- Operate
        self:declare_destination(destination),
        destination,
        " = ",
        first_source,
        " ",
        operation,
        " ",
        second_source,
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

local function conditional_trap(self, _, first_source, second_source, _, _, function_field)
    -- The 0x01 bit specifies whether to perform signed or unsigned comparison.
    local comparison_is_unsigned = bit.band(function_field, 0x01) ~= 0

    -- The 0x02 bit specifies whether to invert the comparison result.
    -- This turns a greater-than-or-equal comparison to a less-than comparison, 
    -- and an equality test to an inequality test.
    local invert_comparison = bit.band(function_field, 0x02) ~= 0

    -- The 0x04 bit specifies whether to use greater-than-or-equal comparison or an equality test.
    local comparison_is_equality = bit.band(function_field, 0x04) ~= 0

    assert(not(comparison_is_equality and comparison_is_unsigned), "reserved instruction: trap on unsigned (in)equality")

    local compare_type = comparison_is_unsigned and "uint64_t" or "int64_t"
    local invert = invert_comparison and "not" or ""
    local operation = comparison_is_equality and "==" or ">="

    first_source = mips.register_name(first_source)
    second_source = mips.register_name(second_source)

    local op = {
        -- Operands
        self:declare_source(first_source),
        self:declare_source(second_source),
        -- Operate
        "assert(",
        invert,
        "(ffi.cast(\"",
        compare_type,
        "\", ",
        first_source,
        ") ",
        operation,
        " ffi.cast(\"",
        compare_type,
        "\", ",
        second_source,
        ")) ,\"conditional trap\")\n"
    }

    return true, table.concat(op)
end

local function conditional_move(self, _, first_source, second_source, destination, _, function_field)
    -- The 0x01 bit signifies whether to invert the equality test.
    local invert_test = bit.band(function_field, 0x01)
    
    local operation = invert_test and "~=" or "=="

    first_source = mips.register_name(first_source)
    second_source = mips.register_name(second_source)
    destination = mips.register_name(destination)

    local op = {
        -- Operands
        self:declare_source(first_source),
        self:declare_source(second_source),
        -- MOV[N/Z] don't touch the destination register if the condition is false.
        self:declare_source(destination), 
        -- Operate
        "if ",
        second_source,
        " ",
        operation,
        " 0 then ",
        self:declare_destination(destination),
        first_source,
        " end\n"
    }

    return true, table.concat(op)
end

local function set_if_less_than(self, _, first_source, second_source, destination, _, function_field)
    -- The 0x01 bit specifies whether to perform signed or unsigned comparison.
    local comparison_is_unsigned = bit.band(function_field, 0x01) ~= 0

    local compare_type = comparison_is_unsigned and "uint64_t" or "int64_t"

    first_source = mips.register_name(first_source)
    second_source = mips.register_name(second_source)
    destination = mips.register_name(destination)

    local op = {
        -- Operands
        self:declare_source(first_source),
        self:declare_source(second_source),
        self:declare_destination(destination), 
        -- Operate
        "(ffi.cast(\"",
        compare_type,
        "\", ",
        first_source,
        ") < ffi.cast(\"",
        compare_type,
        "\", ",
        second_source,
        ") and 1 or 0\n",
    }

    return table.concat(op), true
end

local special_table = {
    shift_immediate,        -- SLL
    shift_immediate,
    shift_immediate,        -- SRL
    shift_immediate,        -- SRA
    shift_variable,         -- SLLV
    shift_variable,
    shift_variable,         -- SRLV
    shift_variable,         -- SRAV
    {},                     -- JR
    {},                     -- JALR
    conditional_move,       -- MOVZ
    conditional_move,       -- MOVN
    {},                     -- SYSCALL
    {},                     -- BREAK
    util.illegal_instruction,
    {},                     -- SYNC
    {},                     -- MFHI
    {},                     -- MTHI
    {},                     -- MFLO
    {},                     -- MTLO
    shift_variable,         -- DSLLV
    shift_variable,
    shift_variable,         -- DSRLV
    shift_variable,         -- DSRAV
    {},                     -- MULT
    {},                     -- MULTU
    {},                     -- DIV
    {},                     -- DIVU
    util.illegal_instruction,    -- (DMULT)
    util.illegal_instruction,    -- (DMULTU)
    util.illegal_instruction,    -- (DDIV)
    util.illegal_instruction,    -- (DDIVU)
    addsub_register,        -- ADD
    addsub_register,        -- ADDU
    addsub_register,        -- SUB
    addsub_register,        -- SUBU
    bitop_register,         -- AND
    bitop_register,         -- OR
    bitop_register,         -- XOR
    bitop_register,         -- NOR
    {},                     -- MFSA
    {},                     -- MTSA
    set_if_less_than,       -- SLT
    set_if_less_than,       -- SLTU
    addsub_register,        -- DADD
    addsub_register,        -- DADDU
    addsub_register,        -- DSUB
    addsub_register,        -- DSUBU
    conditional_trap,       -- TGE
    conditional_trap,       -- TGEU
    conditional_trap,       -- TLT
    conditional_trap,       -- TLTU
    conditional_trap,       -- TEQ
    conditional_trap,
    conditional_trap,       -- TNE
    conditional_trap,
    shift_immediate,        -- DSLL
    shift_immediate,
    shift_immediate,        -- DSRL
    shift_immediate,        -- DSRA
    shift_immediate,        -- DSLL32
    shift_immediate,
    shift_immediate,        -- DSRL32
    shift_immediate,        -- DSRA32
}

return special_table

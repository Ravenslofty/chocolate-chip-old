local decode_mips = require("cc2.decode_mips")

local decode = {}

local function sign_extend_32_64(register)
    return table.concat({
        destination,
        " = arshift(lshift(", 
        destination, 
        ", 32), 32)\n"
    })
end

local function illegal_instruction(_, _, _, _, _, _, _)
    return false, ""
end

local function shift_immediate(self, _, _, second_source, destination, shift_amount, function_field)
    local op_table = {
        [0x00] = "lshift",  -- SLL
        -- 0x01 is illegal
        [0x02] = "rshift",  -- SRL
        [0x03] = "arshift", -- SRA
        [0x38] = "lshift",  -- DSLL
        -- 0x39 is illegal
        [0x3A] = "rshift",  -- DSRL
        [0x3B] = "arshift", -- DSRA
        [0x3C] = "lshift",  -- DSLL32
        -- 0x3D is illegal
        [0x3E] = "rshift",  -- DSRL32
        [0x3F] = "arshift"  -- DSRA32
    }

    -- -32 instructions use shift_amount + 32
    local shift_base = {
        [0x00] = 0,  -- SLL
        -- 0x01 is illegal
        [0x02] = 0,  -- SRL
        [0x03] = 0,  -- SRA
        [0x38] = 0,  -- DSLL
        -- 0x39 is illegal
        [0x3A] = 0,  -- DSRL
        [0x3B] = 0,  -- DSRA
        [0x3C] = 32, -- DSLL32
        -- 0x3D is illegal
        [0x3E] = 32, -- DSRL32
        [0x3F] = 32  -- DSRA32
    }

    -- 32-bit instructions need sign-extension
    local needs_sign_extend = {
        [0x00] = true,  -- SLL
        -- 0x01 is illegal
        [0x02] = true,  -- SRL
        [0x03] = true,  -- SRA
        [0x38] = false, -- DSLL
        -- 0x39 is illegal
        [0x3A] = false, -- DSRL
        [0x3B] = false, -- DSRA
        [0x3C] = false, -- DSLL32
        -- 0x3D is illegal
        [0x3E] = false, -- DSRL32
        [0x3F] = false  -- DSRA32
    }

    second_source = decode_mips.register_name(second_source)
    destination = decode_mips.register_name(destination)

    local op = {
        -- Operands
        self:declare_source(second_source),
        self:declare_destination(destination),
        -- Shift
        destination,
        " = ",
        op_table[function_field],
        "(",
        second_source,
        ", ",
        tostring(shift_amount),
        ")\n",
    }

    if needs_sign_extend[function_field] then
        op[#op + 1] = sign_extend_32_64(destination)
    end

    return table.concat(op)
end

local function shift_variable(self, _, first_source, second_source, destination, _, function_field)
    local op_table = {
        [0x04] = "lshift",  -- SLLV
        -- 0x05 is illegal
        [0x06] = "rshift",  -- SRLV
        [0x07] = "arshift", -- SRAV
        [0x14] = "lshift",  -- DSLLV
        -- 0x15 is illegal
        [0x16] = "rshift",  -- DSRLV
        [0x17] = "arshift"  -- DSRAV
    }

    -- 32-bit instructions need sign-extension
    local needs_sign_extend = {
        [0x04] = true,  -- SLLV
        -- 0x05 is illegal
        [0x06] = true,  -- SRLV
        [0x07] = true,  -- SRAV
        [0x14] = false, -- DSLLV
        -- 0x15 is illegal
        [0x16] = false, -- DSRLV
        [0x17] = false  -- DSRAV
    }

    -- 32-bit instructions use the low 5 bits, 64-bit instructions use the low 6 bits.
    local mask = {
        [0x04] = 0x1F, -- SLLV
        -- 0x05 is illegal
        [0x06] = 0x1F, -- SRLV
        [0x07] = 0x1F, -- SRAV
        [0x14] = 0x3F, -- DSLLV
        -- 0x15 is illegal
        [0x16] = 0x3F, -- DSRLV
        [0x17] = 0x3F  -- DSRAV
    }

    first_source = decode_mips.register_name(first_source)
    second_source = decode_mips.register_name(second_source)
    destination = decode_mips.register_name(destination)

    local op = {
        -- Operands
        self:declare_source(first_source),
        self:declare_source(second_source),
        self:declare_destination(destination),
        -- Shift
        destination,
        " = ",
        op_table[function_field],
        "(",
        second_source,
        ", band(",
        first_source,
        ",",
        tostring(mask[function_field]),
        "))\n",
    }

    return table.concat(op)
end

local function bitop_register(self, _, first_source, second_source, destination, _, function_field)
    local op_table = {
        [0x24] = "band",     -- AND
        [0x25] = "bor",      -- OR
        [0x16] = "bxor",     -- XOR
        [0x17] = "bnot(bor(" -- NOR
    }

    local end_bracket = {
        [0x24] = "", -- AND
        [0x25] = "", -- OR
        [0x26] = "", -- XOR
        [0x27] = ")" -- NOR
    }

    first_source = decode_mips.register_name(first_source)
    second_source = decode_mips.register_name(second_source)
    destination = decode_mips.register_name(destination)

    local op = {
        -- Operands
        self:declare_source(first_source),
        self:declare_source(second_source),
        self:declare_destination(destination),
        -- Shift
        destination,
        " = ",
        op_table[function_field],
        "(",
        first_source,
        ", ",
        second_source,
        ")",
        end_bracket[function_field],
        "\n"
    }

    return table.concat(op)
end

local special_table = {
    shift_immediate,        -- SLL
    illegal_instruction,
    shift_immediate,        -- SRL
    shift_immediate,        -- SRA
    shift_variable,         -- SLLV
    illegal_instruction,
    shift_variable,         -- SRLV
    shift_variable,         -- SRAV
    {},                     -- JR
    {},                     -- JALR
    {},                     -- MOVZ
    {},                     -- MOVN
    {},                     -- SYSCALL
    {},                     -- BREAK
    illegal_instruction,
    {},                     -- SYNC
    {},                     -- MFHI
    {},                     -- MTHI
    {},                     -- MFLO
    {},                     -- MTLO
    shift_variable,         -- DSLLV
    illegal_instruction,
    shift_variable,         -- DSRLV
    shift_variable,         -- DSRAV
    {},                     -- MULT
    {},                     -- MULTU
    {},                     -- DIV
    {},                     -- DIVU
    illegal_instruction,    -- (DMULT)
    illegal_instruction,    -- (DMULTU)
    illegal_instruction,    -- (DDIV)
    illegal_instruction,    -- (DDIVU)
    {},                     -- ADD
    {},                     -- ADDU
    {},                     -- SUB
    {},                     -- SUBU
    bitop_register,         -- AND
    bitop_register,         -- OR
    bitop_register,         -- XOR
    bitop_register,         -- NOR
    {},                     -- MFSA
    {},                     -- MTSA
    {},                     -- SLT
    {},                     -- SLTU
    {},                     -- DADD
    {},                     -- DADDU
    {},                     -- DSUB
    {},                     -- DSUBU
    {},                     -- TGE
    {},                     -- TGEU
    {},                     -- TLT
    {},                     -- TLTU
    {},                     -- TEQ
    illegal_instruction,
    {},                     -- TNE
    illegal_instruction,
    shift_immediate,        -- DSLL
    illegal_instruction,
    shift_immediate,        -- DSRL
    shift_immediate,        -- DSRA
    shift_immediate,        -- DSLL32
    illegal_instruction,
    shift_immediate,        -- DSRL32
    shift_immediate,        -- DSRA32
}

local decode_table = {
    { 0, 0x3F, special_table },
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

local function declare_source(self, register)
    if self.declared[register] then
        return ""
    end
    
    self.declared[register] = true

    if register ~= "zero" then
        return "local " .. name .. " = s.gpr[" .. register .. "]\n"
    end

    return "local zero = 0\n"
end

local function declare_destination(self, register)
    if self.declared[register] then
        return ""
    end

    self.declared[register] = true

    if register ~= "zero" then
        return "local "
    end

    return ""
end

function decode:new()
    local decoder = mips_decode:new(decode_table)
    decoder.declare_source = declare_source
    decoder.declare_destination = declare_destination
    return decoder
end

return decode

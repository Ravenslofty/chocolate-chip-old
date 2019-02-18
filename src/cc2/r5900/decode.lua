local mips = require("cc2.decode_mips")
local util = require("cc2.r5900.decode_util")

local decode = {}

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

    second_source = mips.register_name(second_source)
    destination = mips.register_name(destination)

    local op = {
        -- Operands
        self:declare_source(second_source),
        -- Shift
        self:declare_destination(destination),
        op_table[function_field],
        "(",
        second_source,
        ", ",
        tostring(shift_amount),
        ")\n",
    }

    if needs_sign_extend[function_field] then
        op[#op + 1] = util.sign_extend_32_64(destination)
    end

    return true, table.concat(op)
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
        tostring(mask[function_field]),
        "))\n",
    }

    return true, table.concat(op)
end

local function bitop_register(self, _, first_source, second_source, destination, _, function_field)
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
    local op_table = {
        [0x20] = "+", -- ADD
        [0x21] = "+", -- ADDU
        [0x22] = "-", -- SUB
        [0x23] = "-", -- SUBU
        [0x2C] = "+", -- DADD
        [0x2D] = "+", -- DADDU
        [0x2E] = "-", -- DSUB
        [0x2F] = "-"  -- DSUBU
    }

    -- 32-bit instructions need sign-extension
    local needs_sign_extend = {
        [0x20] = true,  -- ADD
        [0x21] = true,  -- ADDU
        [0x22] = true,  -- SUB
        [0x23] = true,  -- SUBU
        [0x2C] = false, -- DADD
        [0x2D] = false, -- DADDU
        [0x2E] = false, -- DSUB
        [0x2F] = false  -- DSUBU
    }

    -- Non-U operations trap on overflow.
    local needs_overflow_check = {
        [0x20] = true,  -- ADD
        [0x21] = false, -- ADDU
        [0x22] = true,  -- SUB
        [0x23] = false, -- SUBU
        [0x2C] = true,  -- DADD
        [0x2D] = false, -- DADDU
        [0x2E] = true,  -- DSUB
        [0x2F] = false  -- DSUBU
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
        destination,
        " = ",
        first_source,
        " ",
        op_table[function_field],
        " ",
        second_source,
        "\n"
    }

    if needs_overflow_check[function_field] then
        -- TODO: Overflow checking.
    end

    if needs_sign_extend[function_field] then
        op[#op + 1] = util.sign_extend_32_64(destination)
    end

    return true, table.concat(op)
end

local function conditional_trap(self, _, first_source, second_source, _, _, function_field)
    local op_table = {
        [0x30] = ">=", -- TGE
        [0x31] = ">=", -- TGEU
        [0x32] = "<",  -- TLT
        [0x33] = "<",  -- TLTU
        [0x34] = "==", -- TEQ
        -- 0x35 is illegal
        [0x36] = "~=", -- TNE
        -- 0x37 is illegal
    }

    local compare_type = {
        [0x30] = "int64_t", -- TGE
        [0x31] = "uint64_t", -- TGEU
        [0x32] = "int64_t",  -- TLT
        [0x33] = "uint64_t",  -- TLTU
        [0x34] = "int64_t", -- TEQ
        -- 0x35 is illegal
        [0x36] = "int64_t", -- TNE
        -- 0x37 is illegal
    }

    first_source = mips.register_name(first_source)
    second_source = mips.register_name(second_source)

    local op = {
        -- Operands
        self:declare_source(first_source),
        self:declare_source(second_source),
        -- Operate
        "assert(ffi.cast(\"",
        compare_type[function_field],
        "\", ",
        first_source,
        ") ",
        op_table[function_field],
        " ffi.cast(\"",
        compare_type[function_field],
        "\", ",
        second_source,
        ") ,\"conditional trap\")\n"
    }

    return true, table.concat(op)
end

local function conditional_move(self, _, first_source, second_source, destination, _, function_field)
    local op_table = {
        [0x0A] = "==", -- MOVZ
        [0x0B] = "~="  -- MOVN
    }

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
        op_table[function_field],
        " 0 then ",
        self:declare_destination(destination),
        first_source,
        " end\n"
    }

    return true, table.concat(op)
end

local special_table = {
    shift_immediate,        -- SLL
    util.illegal_instruction,
    shift_immediate,        -- SRL
    shift_immediate,        -- SRA
    shift_variable,         -- SLLV
    util.illegal_instruction,
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
    util.illegal_instruction,
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
    {},                     -- SLT
    {},                     -- SLTU
    addsub_register,        -- DADD
    addsub_register,        -- DADDU
    addsub_register,        -- DSUB
    addsub_register,        -- DSUBU
    conditional_trap,       -- TGE
    conditional_trap,       -- TGEU
    conditional_trap,       -- TLT
    conditional_trap,       -- TLTU
    conditional_trap,       -- TEQ
    util.illegal_instruction,
    conditional_trap,       -- TNE
    util.illegal_instruction,
    shift_immediate,        -- DSLL
    util.illegal_instruction,
    shift_immediate,        -- DSRL
    shift_immediate,        -- DSRA
    shift_immediate,        -- DSLL32
    util.illegal_instruction,
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
    if register == "zero" then
        return "local _ = " -- dead placeholder
    end

    local prefix = self.declared[register] and "" or "local "

    self.declared[register] = true
    
    return prefix .. register .. " = "
end

function decode:new()
    local decoder = mips_decode:new(decode_table)
    decoder.declare_source = declare_source
    decoder.declare_destination = declare_destination
    return decoder
end

return decode

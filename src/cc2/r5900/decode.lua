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

local function shift32_immediate(self, _, _, second_source, destination, shift_amount, function_field)
    local op_table = {
        [0x00] = "lshift", -- SLL
        -- 0x01 is illegal
        [0x02] = "rshift", -- SRL
        [0x03] = "arshift" -- SRA
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
        -- Sign-extend
        sign_extend_32_64(destination)
    }

    return table.concat(op)
end

local function shift64_immediate(self, _, _, second_source, destination, shift_amount, function_field)
    local op_table = {
        [0x38] = "lshift",  -- DSLL
        -- 0x39 is illegal
        [0x3A] = "rshift",  -- DSRL
        [0x3B] = "arshift", -- DSRA
        [0x3C] = "lshift",  -- DSLL32
        -- 0x3D is illegal
        [0x3E] = "rshift",  -- DSRL32
        [0x3F] = "arshift"  -- DSRA32
    }

    local shift_base = {
        [0x38] = 0,  -- DSLL
        -- 0x39 is illegal
        [0x3A] = 0,  -- DSRL
        [0x3B] = 0,  -- DSRA
        [0x3C] = 32, -- DSLL32
        -- 0x3D is illegal
        [0x3E] = 32, -- DSRL32
        [0x3F] = 32  -- DSRA32
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
        tostring(shift_base[function_field] + shift_amount),
        ")\n"
    }

    return table.concat(op)
end

local special_table = {
    shift32_immediate,      -- SLL
    illegal_instruction,
    shift32_immediate,      -- SRL
    shift32_immediate,      -- SRA
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
    shift32_immediate,      -- DSLL
    illegal_instruction,
    shift32_immediate,      -- DSRL
    shift32_immediate,      -- DSRA
    shift32_immediate,      -- DSLL32
    illegal_instruction,
    shift32_immediate,      -- DSRL32
    shift32_immediate,      -- DSRA32
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

local decode_mips = require("cc2.decode_mips")

local decode = {}

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
        self:declare_source(second_source),
        self:declare_destination(destination),
        destination,
        " = ",
        op_table[function_field],
        "(",
        second_source,
        ", ",
        tostring(shift_amount),
        ")\n"
    }

    return table.concat(op)
end

local special_table = {
    shift32_immediate,
    illegal_instruction,
    shift32_immediate,
    shift32_immediate,
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

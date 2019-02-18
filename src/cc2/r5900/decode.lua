local mips = require("cc2.decode_mips")
local util = require("cc2.r5900.decode_util")

local decode = {}

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

local decode_util = {}

function decode_util.declare_source(self, register)
    if self.declared[register] then
        return ""
    end
    
    self.declared[register] = true

    if register ~= "zero" then
        return "local " .. name .. " = s.gpr[" .. register .. "]\n"
    end

    return "local zero = 0\n"
end

function decode_util.declare_destination(self, register)
    if register == "zero" then
        return "local _ = " -- dead placeholder
    end

    local prefix = self.declared[register] and "" or "local "

    self.declared[register] = true
    
    return prefix .. register .. " = "
end


function decode_util.sign_extend_32_64(register)
    return table.concat({
        destination,
        " = arshift(lshift(", 
        destination, 
        ", 32), 32)\n"
    })
end

function decode_util.illegal_instruction(_, _, _, _, _, _, _)
    return false, ""
end

return decode_util

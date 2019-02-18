local decode_util = {}

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

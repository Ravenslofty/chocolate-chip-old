local mips = require("cc2.decode_mips")

local decode_util = {}

function decode_util.cop0_register_name(register)
    local register_names = {
        "c0_index",
        "c0_random",
        "c0_entrylo0",
        "c0_entrylo1",
        "c0_context",
        "c0_pagemask",
        "c0_wired",
        "c0_reserved7",
        "c0_badvaddr",
        "c0_count",
        "c0_entryhi",
        "c0_compare",
        "c0_status",
        "c0_cause",
        "c0_epc",
        "c0_prid",
        "c0_config",
        "c0_reserved17",
        "c0_reserved18",
        "c0_reserved19",
        "c0_reserved20",
        "c0_reserved21",
        "c0_reserved22",
        "c0_badpaddr",
        "c0_debug",
        "c0_perf",
        "c0_reserved26",
        "c0_reserved27",
        "c0_taglo",
        "c0_taghi",
        "c0_errorepc",
        "c0_reserved31"
    }

    return register_names[register]
end

function decode_util.declare_source(self, register)
    assert(type(register) == "number")

    if self.gpr_declared[register] then
        return ""
    end
    
    self.gpr_declared[register] = true

    if register ~= 0 then
        local name = mips.register_name(register)
        return "local " .. name .. " = s.gpr[" .. register .. "]\n"
    end

    return "local zero = 0\n"
end

function decode_util.declare_destination(self, register)
    assert(type(register) == "number")

    if register == 0 then
        return "local _ = "
    end

    local prefix = self.gpr_declared[register] and "" or "local "

    self.gpr_declared[register] = true
    self.gpr_needs_writeback[register] = true

    local name = mips.register_name(register)
    
    return prefix .. name .. " = "
end

function decode_util.declare_cop0_source(self, register)
    assert(type(register) == "number")

    if self.cp0r_declared[register] then
        return ""
    end
    
    self.cp0r_declared[register] = true

    local name = decode_util.cop0_register_name(register)
    return "local " .. name .. " = s.cp0r[" .. register .. "]\n"
end

function decode_util.declare_cop0_destination(self, register)
    assert(type(register) == "number")

    -- TODO: detect and ignore writes to read-only registers.

    local prefix = self.cp0r_declared[register] and "" or "local "

    self.cp0r_declared[register] = true
    self.cp0r_needs_writeback[register] = true

    local name = decode_util.cop0_register_name(register)
    return prefix .. name .. " = "
end

function decode_util.sign_extend_32_64(register)
    return table.concat({
        destination,
        " = arshift(lshift(", 
        destination, 
        ", 32), 32)\n"
    })
end

function decode_util.branch_target_address(self, target3, target2, target1)
    local addr = bit.bor(bit.lshift(target3, 11), bit.lshift(target2, 6), target1)
    addr = bit.arshift(bit.lshift(addr, 16), 14) -- Sign extend from 16 to 18 bits.
    return addr + self.program_counter
end

function decode_util.construct_immediate(imm3, imm2, imm1)
    return bit.bor(bit.lshift(imm3, 11), bit.lshift(imm2, 6), imm1)
end

function decode_util.illegal_instruction(_, _, _, _, _, _, _)
    return false, ""
end

return decode_util

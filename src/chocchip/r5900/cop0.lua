local ffi = require("ffi")

local utils = require("chocchip.utils")

local cop0 = {
    -- 32 32-bit system control coprocessor registers.
    gprs = ffi.new("uint32_t[32]"),

    -- COP0 register names
    reg_names = utils.protect({
        INDEX = 0,
        RANDOM = 1,
        ENTRY_LO0 = 2,
        ENTRY_LO1 = 3,
        CONTEXT = 4,
        PAGE_MASK = 5,
        WIRED = 6,
        -- 7 is reserved
        BADVADDR = 8,
        COUNT = 9,
        ENTRY_HI = 10,
        COMPARE = 11,
        STATUS = 12,
        CAUSE = 13,
        EPC = 14,
        PRID = 15,
        CONFIG = 16,
        -- 17-22 are reserved
        BADPADDR = 23,
        DEBUG = 24,
        PERF = 25,
        -- 26-27 are reserved
        TAG_LO = 28,
        TAG_HI = 29,
        ERROREPC = 30,
        -- 31 is reserved.
    })
}

-- Not all the COP0 registers are valid.
function cop0.valid_gpr(reg)
    return true
end

-- And of the valid registers, not all of them are writable.
function cop0.writable_gpr(reg)
    return true
end

-- Read a COP0 register.
-- TODO: Map illegal reads correctly.
function cop0:read_gpr(reg)
    if self.valid_gpr(reg) == false then
        print("NYI: Read from invalid COP0 register")
        os.exit(1)
    else
        return self.gprs[reg]
    end
end

-- Write a COP0 register.
-- TODO: CEN64-style register masking.
function cop0:write_gpr(reg, value)
    if self.valid_gpr(reg) and self.writable_gpr(reg) then
        self.gprs[reg] = value
    end
end

-- Update after a cycle.
function cop0:cycle_update()
    -- Update Random register.
    self.gprs[self.reg_names.RANDOM] = self.gprs[self.reg_names.RANDOM] - 1
    if self.gprs[self.reg_names.RANDOM] == self.gprs[self.reg_names.WIRED] then
        self:write_gpr(self.reg_names.RANDOM, 47)
    end
end

-- Create a new COP0.
function cop0:new()
    ffi.fill(self.gprs, 32*ffi.sizeof("uint32_t"))

    self:write_gpr(self.reg_names.RANDOM, 47)
    self:write_gpr(self.reg_names.PRID, 0x2E10)

    return self
end

return cop0

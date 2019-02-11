local ffi = require("ffi")
local bit = require("bit")

local utils = require("chocchip.utils")

local band = bit.band
local lshift = bit.lshift

local timer = {
    -- MODE: configuration register.
    -- COUNT: counter value.
    -- COMP: compare value.
    -- HOLD: COUNT value at time of SBUS interrupt.
    regs = ffi.new("uint32_t[4]"),
    cycles_until_increment = 0
}

local constants = utils.protect({
    MODE = 0,
    COUNT = 1,
    COMP = 2,
    HOLD = 3,

    -- Clock Selection - set clock frequency.
    MODE_CLKS = 3,
    -- Count Up Enable - enables timer.
    MODE_CUE = lshift(1, 7),

    -- Approximate HBlank interval for PAL in bus cycles.
    HBLANK_PAL = 4719
})

function timer:read_gpr(reg)
    assert(reg < 4, "register index is too large")

    reg = tonumber(reg)

    return self.regs[reg]
end

function timer:write_gpr(reg, value)
    assert(reg < 4, "register index is too large")

    reg = tonumber(reg)

    self.regs[reg] = value

    if self:is_enabled() then
        self.cycles_until_increment = self:update_frequency()
    end
end

function timer:is_enabled()
    local mode = self:read_gpr(constants.MODE)

    return band(mode, constants.MODE_CUE) ~= 0
end

function timer:update_frequency()
    local mode = self:read_gpr(constants.MODE)
    local clock = band(mode, constants.MODE_CLKS)

    -- Bus Clock frequency.
    if clock == 0 then
        return 1
    -- Bus Clock / 16.
    elseif clock == 1 then
        return 16
    -- Bus Clock / 256
    elseif clock == 2 then
        return 256
    -- HBlank frequency.
    -- TODO: This should come from the PCRTC.
    elseif clock == 3 then
        return constants.HBLANK_PAL
    end
end

function timer:cycle_update()
    if not self:is_enabled() then
        return
    end

    self.cycles_until_increment = self.cycles_until_increment - 1

    if self.cycles_until_increment == 0 then
        self.regs[constants.COUNT] = self.regs[constants.COUNT] + 1

        if self.regs[constants.COUNT] == 65536 then
            print("NYI: Timer overflow")
            os.exit(1)
        end

        self.cycles_until_increment = self:update_frequency()
    end
end

function timer:new()
    self.regs = ffi.new("uint32_t[4]")

    return self
end

return timer

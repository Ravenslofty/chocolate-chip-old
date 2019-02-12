local ffi = require("ffi")
local bit = require("bit")

local band = bit.band
local lshift = bit.lshift

local timer = {}

local constants = {
    COUNT = 0,
    MODE = 1,
    COMP = 2,
    HOLD = 3,

    -- Clock Selection - set clock frequency.
    MODE_CLKS = 3,
    -- Count Up Enable - enables timer.
    MODE_CUE = 0x80, --lshift(1, 7),

    -- Approximate HBlank interval for PAL in bus cycles.
    HBLANK_PAL = 4719
}

local instance = {}

function instance:update_frequency()
    local mode = self:read_gpr(constants.MODE)
    local clock = band(mode, constants.MODE_CLKS)

    local clocks = {
        -- Bus Clock frequency.
        1,
        -- Bus Clock / 16.
        16,
        -- Bus Clock / 256
        256,
        -- HBlank frequency.
        constants.HBLANK_PAL
    }

    return clocks[clock]
end

function instance:read_gpr(reg)
    assert(reg < 4, "register index is too large")

    return self.regs[reg]
end

function instance:write_gpr(reg, data)
    assert(reg < 4, "register index is too large")

    self.regs[reg] = data

    self.is_enabled = band(self:read_gpr(constants.MODE), constants.MODE_CUE) ~= 0

    if self.is_enabled then
        self.cycles_until_increment = self:update_frequency()
    end
end

function instance:cycle_update()
    if not self.is_enabled then
        return
    end

    self.cycles_until_increment = self.cycles_until_increment - 1

    if self.cycles_until_increment == 0 then
        self.regs[constants.COUNT] = self.regs[constants.COUNT] + 1

        if self.regs[constants.COUNT] == 65536 then
            self.regs[constants.COUNT] = 0
            print("NYI: timer overflow")
            --os.exit(1)
        end

        self.cycles_until_increment = self:update_frequency()
    end
end

local TimerInstance = {__index = instance}

function timer.new()
    return setmetatable({
        regs = ffi.new("int32_t[16]"),
        cycles_until_increment = 0,
        is_enabled = false
    }, TimerInstance)
end

return timer

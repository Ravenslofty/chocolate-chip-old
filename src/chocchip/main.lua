local ffi = require("ffi")
local bit = require("bit")

local r5900_decode = require "chocchip.r5900.decode"
local r5900_interpret = require "chocchip.r5900.interpret"
--local r5900_tlb = require "chocchip.r5900.tlb"

local band, bor = bit.band, bit.bor
local lshift, rshift = bit.lshift, bit.rshift

local main = {
    setup = false,

    -- RDRAM.
    rdram = nil,
    rdram_size = 0,

    -- DMAC registers.
    dmac_config_reg = nil,

    -- BIOS data.
    bios = nil,

    -- R5900 CPU.
    tlb = nil
}

function main:init()
    if self.setup then
        return
    end

    -- Load BIOS
    local f = assert(io.open("bios.bin", "r"), "Couldn't open BIOS")
    local data = f:read("*all")
    f:close()

    assert(#data == 4*1024*1024, "size of BIOS is incorrect: " .. #data)

    self.bios = ffi.new("uint8_t[4*1024*1024]", data)
    self.rdram = ffi.new("uint8_t[32*1024*1024]")
    self.spram = ffi.new("uint8_t[16*1024]")

    self.dmac_config_reg = ffi.new("uint32_t[16]")

    --self.tlb = r5900_tlb:new()

    self.setup = true
end

function main.translate(vaddr)
    vaddr = band(vaddr, 0xFFFFFFFF)

    if vaddr >= 0x70000000 and vaddr < 0x70004000 then
        return true, band(vaddr, bit.bnot(0x70000000))
    else
        return false, band(vaddr, 0x1FFFFFFF)
    end
end

function r5900_interpret.read4(vaddr)
    assert(vaddr % 4 == 0, "virtual address is not 4-byte aligned")

    local scratchpad, paddr = main.translate(vaddr)

    -- Scratchpad RAM.
    if scratchpad then
        local data = 0
        for i=0,3 do
            local byte = main.spram[paddr+i]
            data = bor(lshift(data, 8), byte)
        end
        return data
    -- RDRAM.
    elseif paddr >= 0 and paddr <= main.rdram_size then
        local data = 0
        for i=0,3 do
            local byte = main.rdram[paddr+i]
            data = bor(rshift(data, 8), lshift(byte, 24))
        end
        return data
    -- DMAC configuration registers.
    elseif paddr >= 0x1000f500 and paddr <= 0x1000f5f0 then
        local reg = rshift(band(paddr, 0xf0), 2)
        return main.dmac_config_reg[reg]
    -- BIOS ROM.
    elseif paddr >= 0x1fc00000 and paddr <= 0x20000000 then -- luacheck: ignore
        local addr = paddr - 0x1fc00000
        local data = 0
        for i=0,3 do
            local byte = main.bios[addr+i]
            data = bor(rshift(data, 8), lshift(byte, 24))
        end
        return data
    else
        print("NYI: Unrecognised physical address ", bit.tohex(paddr), "for virtual address", bit.tohex(vaddr))
        os.exit(1)
    end
end

function r5900_interpret.write4(vaddr, data)
    assert(vaddr % 4 == 0, "virtual address is not 4-byte aligned")

    local scratchpad, paddr = main.translate(vaddr)

    -- Scratchpad RAM.
    if scratchpad then
        for i=0,3 do
            local byte = band(rshift(data, i*8), 0xFF)
            main.spram[paddr+i] = byte
        end
    -- RDRAM.
    elseif paddr >= 0 and paddr <= main.rdram_size then
        for i=0,3 do
            local byte = band(rshift(data, i*8), 0xFF)
            main.rdram[paddr+i] = byte
        end
    -- DMAC configuration registers.
    elseif paddr >= 0x1000f500 and paddr <= 0x1000f5f0 then
        local reg = rshift(band(paddr, 0xf0), 2)
        main.dmac_config_reg[reg] = data
    -- BIOS ROM.
    elseif paddr >= 0x1fc00000 and paddr <= 0x20000000 then -- luacheck: ignore
        -- Ignore BIOS writes.
    else
        print("NYI: Unrecognised physical address ", bit.tohex(paddr), "for virtual address", bit.tohex(vaddr))
        os.exit(1)
    end
end

main:init()

-- luacheck: ignore
-- Used by the emitted functions
s = r5900_interpret:new(0xBFC00000)
local t = {}

for i=1,100 do
    --[[for N=29,29 do
        io.write(string.format("%d: %s%s\n", N, bit.tohex(s:read_gpr64(N, 1)), bit.tohex(s:read_gpr64(N, 0))))
    end]]
    local pc = tonumber(s.pc)
    io.write(bit.tohex(pc), "\n")
    if t[pc] == nil then
        local f = r5900_decode.decode(r5900_interpret.read4, pc)
        io.write(f, "\n")
        t[pc] = load(f)
    end
    t[pc]()
end

return main

local ffi = require("ffi")
local bit = require("bit")

local r5900_decode = require "chocchip.r5900.decode"
local r5900_interpret = require "chocchip.r5900.interpret"
local r5900_tlb = require "chocchip.r5900.tlb"

local main = {
    setup = false,

    -- BIOS data.
    bios = nil,

    -- R5900 CPU.
    tlb = r5900_tlb
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

    self.setup = true
end


function main:read_byte(vaddr)
    local paddr = self.tlb:translate(vaddr)

    if paddr >= 0x1fc00000 and paddr <= 0x20000000 then
        paddr = paddr - 0x1fc00000
        return self.bios[paddr]
    else
        print("NYI: Unrecognised physical address " .. bit.tohex(paddr))
        os.exit(1)
    end
end

main:init()

io.write(r5900_decode.decode(main, main.read_byte, 0xbfc00000))

return main

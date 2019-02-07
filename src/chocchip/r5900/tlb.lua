local ffi = require("ffi")
local bit = require("bit")

local band = bit.band

ffi.cdef[[
typedef struct {
    uint32_t page_mask;
    uint32_t entry_hi;
    uint32_t entry_lo1;
    uint32_t entry_lo0;
} TlbEntry;
]]

local tlb = {
    entries = ffi.new("TlbEntry[48]")
}

-- Convert a virtual address to a physical one.
-- TODO: this is a boring direct translation, and is usually wrong.
function tlb:translate(addr, mode)
    return band(addr, 0x1FFFFFFF)
end

return tlb

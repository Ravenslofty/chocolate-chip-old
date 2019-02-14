local ffi = require("ffi")
local bit = require("bit")

local r5900_decode = require("chocchip.r5900.decode")
local r5900_interpret = require("chocchip.r5900.interpret")
local r5900_timer = require("chocchip.r5900.timer")
--local r5900_tlb = require "chocchip.r5900.tlb"

local band, bor = bit.band, bit.bor
local lshift, rshift = bit.lshift, bit.rshift

local main = {}

function main:init()
   -- Load BIOS
   local f = assert(io.open("bios.bin", "r"), "Couldn't open BIOS")
   local data = f:read("*all")
   f:close()

   assert(#data == 4*1024*1024, "size of BIOS is incorrect: " .. #data)

   self.bios = ffi.new("uint8_t[4*1024*1024]", data)
   self.rdram = ffi.new("uint8_t[32*1024*1024]")
   self.rdram_size = 32*1024*1024
   self.spram = ffi.new("uint8_t[16*1024]")

   --self.tlb = r5900_tlb:new()
   self.timers = { r5900_timer.new(), r5900_timer.new(), r5900_timer.new(), r5900_timer.new() }
   self.dmac_config_reg = ffi.new("uint32_t[16]")
   self.gs_special_reg = ffi.new("uint64_t[16]")
   self.gs_config_reg = ffi.new("uint64_t[16]")

   self.setup = true
end

local function translate(vaddr)
   vaddr = band(vaddr, 0xFFFFFFFF)

   if vaddr >= 0x70000000 and vaddr < 0x70004000 then
      return true, band(vaddr, bit.bnot(0x70000000))
   else
      return false, band(vaddr, 0x1FFFFFFF)
   end
end

function r5900_interpret.read4(vaddr)
   local scratchpad, paddr = translate(vaddr)

   --io.write("R: 0x", bit.tohex(paddr), "\n")
   -- Memory
   if paddr >= 0 and paddr <= main.rdram_size then
      local data = 0
      -- Scratchpad RAM.
      if scratchpad then
         assert(paddr <= 16*1024)
         for i=0,3 do
            local byte = main.spram[paddr+i]
            data = bor(rshift(data, 8), lshift(byte, 24))
         end
         return data
      else
      -- RDRAM.
         return bor(
            main.rdram[paddr],
            lshift(main.rdram[paddr+1], 8),
            lshift(main.rdram[paddr+2], 16),
            lshift(main.rdram[paddr+3], 24)
         )
      end
      -- Timers.
   elseif paddr >= 0x10000000 and paddr <= 0x100003f0 then
      local timer = tonumber(rshift(band(paddr, 0xf00), 8) + 1)
      local reg = rshift(band(paddr, 0xf0), 4)
      return main.timers[timer]:read_gpr(reg)
      -- DMAC configuration registers.
   elseif paddr >= 0x1000f500 and paddr <= 0x1000f5f0 then
      local reg = rshift(band(paddr, 0xf0), 2)
      return main.dmac_config_reg[reg]
      -- GS special registers.
   elseif paddr >= 0x12000000 and paddr <= 0x120000f0 then
      local reg = rshift(band(paddr, 0xf0), 2)
      return main.gs_special_reg[reg]
      -- GS configuration registers.
   elseif paddr >= 0x12001000 and paddr <= 0x120010f0 then
      local reg = rshift(band(paddr, 0xf0), 2)
      return main.gs_config_reg[reg]
      -- ????
   elseif paddr == 0x1a000006 then
      return 1
      -- ???? 2
   elseif paddr == 0x1a000000 or paddr == 0x1a000002 or paddr == 0x1a000010 or paddr == 0x1a000012 then
      return 0
      -- "Some IOP shit" - PSI
   elseif paddr == 0x1f803204 or paddr == 0x1f801470 or paddr == 0x1f801472 then
      return 0
      -- BIOS ROM.
   elseif paddr >= 0x1fc00000 and paddr < 0x20000000 then -- luacheck: ignore
      local addr = paddr - 0x1fc00000
      local data = 0
      for i=0,3 do
         local byte = main.bios[addr+i]
         data = bor(rshift(data, 8), lshift(byte, 24))
      end
      return data
   else
      print("NYI: Unrecognised read from physical address", bit.tohex(paddr), "for virtual address", bit.tohex(vaddr))
      os.exit(1)
   end
end

function r5900_interpret.write4(vaddr, data)
   local scratchpad, paddr = translate(vaddr)

   --io.write("W: 0x", bit.tohex(paddr), "\n")

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
      -- Timers
   elseif paddr >= 0x10000000 and paddr <= 0x100003f0 then
      local timer = tonumber(rshift(band(paddr, 0xf00), 8)) + 1
      local reg = rshift(band(paddr, 0xf0), 4)
      main.timers[timer]:write_gpr(reg, tonumber(data))
      -- Serial I/O.
   elseif paddr >= 0x1000f100 and paddr <= 0x1000f1f0 then
      local reg = rshift(band(paddr, 0xf0), 4)
      if reg == 8 then
         io.write(string.char(tonumber(data)))
      end
      -- DMAC configuration registers.
   elseif paddr >= 0x1000f500 and paddr <= 0x1000f5f0 then
      local reg = rshift(band(paddr, 0xf0), 4)
      main.dmac_config_reg[reg] = data
      -- GS special registers.
   elseif paddr >= 0x12000000 and paddr <= 0x120000f0 then
      local reg = rshift(band(paddr, 0xf0), 2)
      main.gs_special_reg[reg] = data
      -- GS configuration registers.
   elseif paddr >= 0x12001000 and paddr <= 0x120010f0 then
      local reg = rshift(band(paddr, 0xf0), 2)
      main.gs_config_reg[reg] = data
      -- ????
   elseif paddr == 0x1a000000 or
      paddr == 0x1a000002 or
      paddr == 0x1a000006 or
      paddr == 0x1a000010 or
      paddr == 0x1a000012 then -- luacheck: ignore
      -- "Some IOP shit" - PSI
   elseif paddr == 0x1f801470 or paddr == 0x1f801472 then -- luacheck: ignore
      -- BIOS ROM.
   elseif paddr >= 0x1fc00000 and paddr <= 0x20000000 then -- luacheck: ignore
      -- Ignore BIOS writes.
   else
      print("NYI: Unrecognised write to physical address ", bit.tohex(paddr), "for virtual address", bit.tohex(vaddr))
      os.exit(1)
   end
end

function r5900_interpret:bus_cycle_update()
   main.timers[1]:cycle_update()
   main.timers[2]:cycle_update()
   main.timers[3]:cycle_update()
   main.timers[4]:cycle_update()
end

main:init()

-- luacheck: ignore
-- Used by the emitted functions
s = r5900_interpret:new(0xBFC00000)

local traces_generated = 0
local traces_executed = 0
local insns_executed = 0

function main.run()
   local t = {}
   local count = {}
   while true do
      --[[for N=3,3 do
      io.write(string.format("%d: %s%s\n", N, bit.tohex(s:read_gpr64(N, 1)), bit.tohex(s:read_gpr64(N, 0))))
      end]]
      local pc = tonumber(s.pc)
      assert(pc ~= 0, "jumped to zero")
      if t[pc] == nil then
         traces_generated = traces_generated + 1
         io.write("PC: ", bit.tohex(pc), "\n")
         local f, c = r5900_decode.decode(r5900_interpret.read4, pc)
         tracefile = assert(io.open("traces/" .. bit.tohex(pc) .. ".lua", "w"))
         tracefile:write(f, "\n")
         tracefile:close()
         assert(load(f))()
         count[pc] = c
         t[pc] = assert(load("x" .. bit.tohex(pc) .. "(s)"))
      end
      t[pc]()
      insns_executed = insns_executed + count[pc]
      traces_executed = traces_executed + 1
   end
end

function main.registers()
   for reg=0,31 do
      print(reg, bit.tohex(s:read_gpr64(reg, 1)), bit.tohex(s:read_gpr64(reg, 0)))
   end
   print("traces generated:", traces_generated)
   print("traces executed:", traces_executed)
   print("insns executed:", insns_executed)
end

function main.crash(err)
   io.write("chocchip: error: ", err, "\n\n")
   --os.exit(1)
end

return main

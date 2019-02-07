local ffi = require("ffi")
local bit = require("bit")

local tlb = require("chocchip.r5900.tlb")
local cop0 = require("chocchip.r5900.cop0")

local band, bor = bit.band, bit.bor
local lshift, rshift, arshift = bit.lshift, bit.rshift, bit.arshift

local interpret = {
    -- 32 128-bit general-purpose registers.
    gprs = ffi.new("uint32_t[32][4]"),
    -- Branch delay slots.
    bd_cond = ffi.new("bool[2]"),
    bd_pc = ffi.new("uint32_t[2]"),
    -- Program counter.
    pc = ffi.new("uint32_t"),

    -- Translation lookaside buffer.
    tlb = tlb,
    -- System control coprocessor.
    cop0 = cop0
}

-- Per-cycle update.
function interpret:cycle_update()
    self.cop0:cycle_update()

    -- Branch delay slot
    if self.bd_cond[0] == true then
        self.pc = self.bd_pc[0]
    end

    self.bd_cond[0] = self.bd_cond[1]
    self.bd_cond[1] = false
    self.bd_pc[0] = self.bd_pc[1]
    self.bd_pc[1] = 0

    self.pc = self.pc + 4
end

-- Read a 32-bit value from a register.
function interpret:read_gpr32(reg, word)
    if reg == 0 then
        return 0
    end
    return self.gprs[reg][word]
end

-- Read a 64-bit value from a register.
function interpret:read_gpr64(reg, dword)
    if reg == 0 then
        return ffi.cast("uint64_t", 0)
    end
    local reg_lo = ffi.cast("uint64_t", self.gprs[reg][2*dword + 0])
    local reg_hi = ffi.cast("uint64_t", self.gprs[reg][2*dword + 1])
    return bor(reg_lo, lshift(reg_hi, 32))
end

-- Write a 32-bit value to a register.
function interpret:write_gpr32(reg, value, word)
    if reg ~= 0 then
        self.gprs[reg][word] = value
    end
end

-- Write a 32-bit value to a register, sign-extending it to 64-bit.
function interpret:write_gpr32_i64(reg, value)
    if reg ~= 0 then
        local sign = band(value, lshift(1, 31))

        self.gprs[reg][0] = value
        if sign == 0 then
            self.gprs[reg][1] = 0
        else
            self.gprs[reg][1] = -1
        end
    end
end

-- Write a 64-bit value to a register.
function interpret:write_gpr64(reg, value)
    if reg ~= 0 then
        local lo = ffi.cast("uint32_t", value)
        local hi = ffi.cast("uint32_t", rshift(value, 32))

        self.gprs[reg][0] = lo
        self.gprs[reg][1] = hi
    end
end

-- MIPS sometimes sign-extends immediates.
function interpret.sign_extend_16_32(value)
    return arshift(lshift(ffi.cast("uint32_t", value), 16), 16)
end

-- MIPS sometimes zero-extends immediates.
function interpret.zero_extend_16_32(value)
    return ffi.cast("uint32_t", value)
end

-- Create a 16-bit immediate.
function interpret.create_imm16(rd, shamt, funct)
    return bor(lshift(rd, 11), lshift(shamt, 6), funct)
end

-- System call.
function interpret:generate_system_call_exception()
    print("NYI: System Call Exception")
    os.exit(1)
end

-- Software breakpoint.
function interpret:generate_breakpoint_exception()
    print("NYI: Breakpoint Exception")
    os.exit(1)
end

-- Illegal instruction.
function interpret:generate_reserved_instruction_exception()
    print("NYI: Reserved Instruction Exception")
    os.exit(1)
end

-- Two's complement overflow exception.
function interpret:generate_overflow_exception()
    print("NYI: Overflow Exception")
    os.exit(1)
end

-- Add.
function interpret:add(_, rs, rt, rd, _, _)
    local rs_lo = self:read_gpr32(rs, 0)
    local rt_lo = self:read_gpr32(rt, 0)

    local value = rs_lo + rt_lo
    if value < rs_lo then
        self:generate_overflow_exception()
    else
        self:write_gpr32_i64(rd, value)
    end
end

-- Add Unsigned.
function interpret:addu(_, rs, rt, rd, _, _)
    local rs_lo = self:read_gpr32(rs, 0)
    local rt_lo = self:read_gpr32(rt, 0)

    local value = rs_lo + rt_lo

    self:write_gpr32_i64(rd, value)
end

-- Add Immediate.
function interpret:addi(_, rs, rt, rd, shamt, funct)
    local rs_lo = self:read_gpr32(rs, 0)
    local imm = self.create_imm16(rd, shamt, funct)

    local value = rs_lo + imm
    if value < rs_lo then
        self:generate_overflow_exception()
    else
        self:write_gpr32_i64(rt, value)
    end
end

-- Add Immediate Unsigned.
function interpret:addiu(_, rs, rt, rd, shamt, funct)
    local rs_lo = self:read_gpr32(rs, 0)
    local imm = self.create_imm16(rd, shamt, funct)

    local value = rs_lo + imm

    self:write_gpr32_i64(rt, value)
end

-- AND. (renamed due to it being a Lua keyword)
function interpret:band(_, rs, rt, rd, _, _)
    local rs_lo = self:read_gpr32(rs, 0)
    local rs_hi = self:read_gpr32(rs, 1)
    local rt_lo = self:read_gpr32(rt, 0)
    local rt_hi = self:read_gpr32(rt, 1)

    local value_lo = band(rs_lo, rt_lo)
    local value_hi = band(rs_hi, rt_hi)

    self:write_gpr32(rd, value_lo, 0)
    self:write_gpr32(rd, value_hi, 1)
end

-- AND Immediate. (renamed for consistency with AND)
-- NB: the immediate is specified to be zero-extended, and anything AND 0 is 0, so we just clear the high 32-bits.
function interpret:bandi(_, rs, rt, rd, shamt, funct)
    local rs_lo = self:read_gpr32(rs, 0)
    local imm = self.create_imm16(rd, shamt, funct)

    local value = band(rs_lo, imm)

    self:write_gpr32(rt, value, 0)
    self:write_gpr32(rt, 0, 1)
end

-- Breakpoint. (renamed due to break being a Lua keyword)
function interpret:bbreak(_, _, _, _, _, _)
    self:generate_breakpoint_exception()
end

-- 64-bit Add.
function interpret:dadd(_, rs, rt, rd, _, _)
    local rs_full = self:read_gpr64(rs, 0)
    local rt_full = self:read_gpr64(rt, 0)

    local value = rs_full + rt_full
    if value < rs_full then
        self:generate_overflow_exception()
    else
        self:write_gpr64(rd, value)
    end
end

-- 64-bit Add Unsigned.
function interpret:daddu(_, rs, rt, rd, _, _)
    local rs_full = self:read_gpr64(rs, 0)
    local rt_full = self:read_gpr64(rt, 0)

    local value = rs_full + rt_full
    self:write_gpr64(rd, value)
end

-- 64-bit Add Immediate.
function interpret:daddi(_, rs, rt, rd, shamt, funct)
    local rs_full = self:read_gpr64(rs, 0)
    local imm = self.create_imm16(rd, shamt, funct)

    local value = rs_full + imm
    if value < rs_full then
        self:generate_overflow_exception()
    else
        self:write_gpr64(rt, value)
    end
end

-- 64-bit Add Immediate Unsigned
function interpret:daddiu(_, rs, rt, rd, shamt, funct)
    local rs_full = self:read_gpr64(rs, 0)
    local imm = self.create_imm16(rd, shamt, funct)

    local value = rs_full + imm
    self:write_gpr64(rt, value)
end

-- Jump to immediate address.
function interpret:j(_, rs, rt, rd, shamt, funct)
    local addr = self.create_imm26(rs, rt, rd, shamt, funct)

    self.bd_cond[1] = true
    self.bd_pc[1] = lshift(addr, 2)
end

-- Jump to immediate address and place the link address in $ra.
function interpret:jal(_, rs, rt, rd, shamt, funct)
    local addr = self.create_imm26(rs, rt, rd, shamt, funct)

    self.bd_cond[1] = true
    self.bd_pc[1] = lshift(addr, 2)
    -- BUG: this is technically wrong at the very edge of the address space.
    self:write_gpr64(31, self.pc + 8)
end

-- Jump to register address.
function interpret:jr(_, rs, _, _, _, _)
    self.bd_cond[1] = true
    self.bd_pc[1] = self:read_gpr32(rs, 0)
end

-- Jump to register address and place the link address in rd.
function interpret:jalr(_, rs, _, rd, _, _)
    self.bd_cond[1] = true
    self.bd_pc[1] = self:read_gpr32(rs, 0)
    self:write_gpr64(rd, self.pc + 8)
end

-- Load 16-bit immediate in upper 16-bits and zero lower 16-bits.
function interpret:lui(_, _, rt, rd, shamt, funct)
    local imm = self.create_imm16(rd, shamt, funct)

    local value = lshift(imm, 16)

    self:write_gpr32_i64(rt, value)
end

-- OR Immediate.
function interpret:ori(_, rs, rt, rd, shamt, funct)
    local imm = self.create_imm16(rd, shamt, funct)
    local rs_full = self:read_gpr64(rs, 0)

    local value = bor(rs_full, imm)

    self:write_gpr64(rt, value)
end

-- Shift Left Logical.
function interpret:sll(_, _, rt, rd, shamt, _)
    local rt_lo = self:read_gpr32(rt, 0)

    local value = lshift(rt_lo, shamt)

    self:write_gpr32_i64(rd, value)
end

-- Shift Left Logical Variable.
function interpret:sllv(_, rs, rt, rd, _, _)
    local rs_lo = self:read_gpr32(rs, 0)
    local rt_lo = band(self:read_gpr32(rt, 0), 31)

    local value = lshift(rs_lo, rt_lo)

    self:write_gpr32_i64(rd, value)
end

-- Shift Right Logical.
function interpret:srl(_, _, rt, rd, shamt, _)
    local rt_lo = self:read_gpr32(rt, 0)

    local value = rshift(rt_lo, shamt)

    self:write_gpr32_i64(rd, value)
end

-- Shift Right Logical Variable.
function interpret:srlv(_, rs, rt, rd, _, _)
    local rs_lo = self:read_gpr32(rs, 0)
    local rt_lo = band(self:read_gpr32(rt, 0), 31)

    local value = rshift(rs_lo, rt_lo)

    self:write_gpr32_i64(rd, value)
end

-- Shift Right Arithmetic.
function interpret:sra(_, _, rt, rd, shamt, _)
    local rt_lo = self:read_gpr32(rt, 0)

    local value = arshift(rt_lo, shamt)

    self:write_gpr32_i64(rd, value)
end

-- Shift Right Arithmetic Variable.
function interpret:srav(_, rs, rt, rd, _, _)
    local rs_lo = self:read_gpr32(rs, 0)
    local rt_lo = band(self:read_gpr32(rt, 0), 31)

    local value = arshift(rs_lo, rt_lo)

    self:write_gpr32_i64(rd, value)
end

for i=1,1000 do
    interpret:lui(15, 0, 1, 2, 8, 52) -- lui $1, 0x1234
    interpret:ori(13, 1, 1, 10, 25, 56) -- ori $1, 0x5678
end

return interpret

local bit = require("bit")

local band, rshift = bit.band, bit.rshift

local mips_decode = {}

function mips_decode.opcode_field(insn)
    return band(rshift(insn, 26), 0x3F)
end

function mips_decode.first_source_reg(insn)
    return band(rshift(insn, 21), 0x1F)
end

function mips_decode.second_source_reg(insn)
    return band(rshift(insn, 16), 0x1F)
end

function mips_decode.destination_reg(insn)
    return band(rshift(insn, 11), 0x1F)
end

function mips_decode.shift_amount(insn)
    return band(rshift(insn, 6), 0x1F)
end

function mips_decode.funct_field(insn)
    return band(insn, 0x3F)
end

return mips_decode

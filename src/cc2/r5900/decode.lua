local mips = require("cc2.decode_mips")
local util = require("cc2.r5900.decode_util")

local general_table = require("cc2.r5900.decode_general")
local special_table = require("cc2.r5900.decode_special")
local regimm_table = require("cc2.r5900.decode_regimm")
local cop0_table = require("cc2.r5900.decode_cop0")

local decode = {}

local decode_table = {
    { 0, 0x3F, special_table },
    { 16, 0x1F, regimm_table },
    {},
    {},
    {},
    {},
    {},
    {},
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    { 26, 0x3F, general_table },
    {},
    {},
    {},
    {},
    { 21, 0x1F, cop0_table },
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
}

function decode:new()
    return mips:new(decode_table)
end

return decode

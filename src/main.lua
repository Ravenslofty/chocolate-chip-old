require("jit.opt").start(
  "maxmcode=8192",
  "maxtrace=2000"
)

local main = require("chocchip.main")

xpcall(main.run, main.crash)
io.write("register state:\n")
main.registers()
io.write("executed instructions: ", tostring(insns_executed), "\n")



require("jit.opt").start(
  "maxmcode=8192",
  "maxtrace=2000"
)

local main = require("chocchip.main")

main.run()
--xpcall(main.run, main.crash)
io.write("register state:\n")
main.registers()



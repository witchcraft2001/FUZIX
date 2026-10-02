
local OUTDIR=os.getenv("FUZIX_MAME_OUT") or "."
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<14 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  local f=assert(io.open(OUTDIR.."/write2.txt","w"))
  f:write(string.format("PC=%04X SP=%04X HALT=%s IFF=%s\n", st["PC"].value, st["SP"].value, tostring(st["HALT"].value), tostring(st["IFF1"].value)))
  f:write(string.format("rst38=%02X noei=%02X doexec=%02X\n", rb(65113), rb(65137), rb(65138)))
  f:write(string.format("@112=%02X%02X @126=%02X u_break=%04X\n", rb(0x0112), rb(0x0113), rb(0x0126), rw(0xEE1E)))
  f:write(string.format("fail_stage=%02X done=%04X\n", rb(65146), rw(65150)))
  f:close()
  manager.machine:exit()
end)

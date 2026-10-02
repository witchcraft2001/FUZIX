local OUTDIR=os.getenv("FUZIX_MAME_OUT") or "."
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<45 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local ios=cpu.spaces["io"]
  local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  local f=assert(io.open(OUTDIR.."/sh_full.txt","w"))
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s\n", t, st["PC"].value, st["SP"].value, tostring(st["HALT"].value)))
  f:write(string.format("fail=%02X done=%04X doexec=%02X seen=%02X noei=%02X dbg15=%02X dbg14=%02X\n",
    rb(65148), rw(65152), rb(65140), rb(65181), rb(65139),
    rb(65186+15), rb(65186+14)))
  f:write(string.format("kp %02X %02X %02X u_break=%04X rst38=%02X\n",
    rb(65101), rb(65101+1), rb(65101+2), rw(60928+0x1E), rb(65115)))
  local k0,u0,u1=rb(65101),rb(60928+2),rb(60928+3)
  if u0>=0x08 and u0<0x50 then ios:write_u8(0x82, u0) end
  if u1>=0x08 and u1<0x50 then ios:write_u8(0xA2, u1) end
  f:write(string.format("u0=%02X u1=%02X @0112=%02X%02X @57FA=%02X%02X%02X%02X\n",
    u0, u1, rb(0x112), rb(0x113), rb(0x57FA), rb(0x57FB), rb(0x57FC), rb(0x57FD)))
  if k0>=0x08 and k0<0x50 then ios:write_u8(0x82, k0) end
  f:close(); manager.machine:exit()
end)

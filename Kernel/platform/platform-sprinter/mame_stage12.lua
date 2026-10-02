
local OUTDIR=os.getenv("FUZIX_MAME_OUT") or "."
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<18 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  local f=assert(io.open(OUTDIR.."/stage12.txt","w"))
  f:write(string.format("PC=%04X SP=%04X HALT=%s IFF=%s\n", st["PC"].value, st["SP"].value, tostring(st["HALT"].value), tostring(st["IFF1"].value)))
  f:write(string.format("fail_stage=%02X err=%02X done=%04X count=%04X\n",
    rb(65146), rb(65147),
    rw(65150), rw(65152)))
  f:write(string.format("rst38=%02X noei=%02X doexec=%02X u_error=%04X\n",
    rb(65113), rb(65137),
    rb(65138), rw(0xEE0C)))
  f:write(string.format("u_page %02X %02X %02X @100=%02X%02X @112=%02X%02X\n",
    rb(0xEE02), rb(0xEE03), rb(0xEE04), rb(0x0100), rb(0x0101), rb(0x0112), rb(0x0113)))
  f:write(string.format("dbg15=%02X u_break=%04X u_top=%04X\n",
    rb(65176+15), rw(0xEE1E), rw(0xEE1C)))
  f:write(string.format("sh_sig=%s\n", (rb(0x0112)==0xD5 and rb(0x0113)==0xD9) and "stock" or "other"))
  f:close()
  manager.machine:exit()
end)

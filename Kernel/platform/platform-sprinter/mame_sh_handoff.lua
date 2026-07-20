local OUTDIR="/Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/mame_out"
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<6.0 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local iosp=cpu.spaces["io"]
  local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  local f=assert(io.open(OUTDIR.."/postsh.txt","w"))
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s I=%02X\n", t, st["PC"].value, st["SP"].value, tostring(st["HALT"].value), st["I"] and st["I"].value or 0))
  f:write(string.format("fail=%02X panic=%04X rst38=%02X ret=%04X\n", rb(0xFE62), rw(0xFE3D), rb(0xFE43), rw(0xFE46)))
  f:write(string.format("mpgsel %02X %02X %02X %02X kp %02X %02X %02X %02X\n",
    rb(0xFE30),rb(0xFE31),rb(0xFE32),rb(0xFE33), rb(0xFE35),rb(0xFE36),rb(0xFE37),rb(0xFE38)))
  f:write(string.format("u_page %02X %02X %02X %02X err=%04X\n", rb(0xEE02),rb(0xEE03),rb(0xEE04),rb(0xEE05), rw(0xEE0C)))
  -- doexec latches if present
  for _,name_addr in ipairs({{"expect",0},{"arm",0}}) do end
  local sp=st["SP"].value
  f:write("stack:")
  for i=0,31 do f:write(string.format(" %02X", rb((sp+i)&0xFFFF))) end
  f:write("\n")
  local pg0=rb(0xEE02)
  iosp:write_u8(0x82,pg0); iosp:write_u8(0xA2,rb(0xEE03)); iosp:write_u8(0xC2,rb(0xEE04))
  f:write("USER100:")
  for i=0,31 do f:write(string.format(" %02X", rb(0x0100+i))) end
  f:write("\n")
  -- compare first bytes to sh
  f:write(string.format("sh_loaded=%s\n", tostring(rb(0x0112)==0xD5 and rb(0x0113)==0xD9)))
  f:close()
  manager.machine:exit()
end)

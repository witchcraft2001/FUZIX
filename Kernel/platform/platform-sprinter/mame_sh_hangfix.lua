-- One-shot dump (no live remapping — that stalls the guest).
local OUTDIR="/Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/mame_out"
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<8.0 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local iosp=cpu.spaces["io"]
  local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  os.execute("mkdir -p "..OUTDIR)
  local f=assert(io.open(OUTDIR.."/hangfix.txt","w"))
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s\n",
    t, st["PC"].value, st["SP"].value, tostring(st["HALT"].value)))
  f:write(string.format("rw=%02X panic=%04X bytes=%02X%02X%02X%02X callno=%02X\n",
    rb(0xFE72), rw(0xFE3D), rb(0xFE3F),rb(0xFE40),rb(0xFE41),rb(0xFE42), rb(0xEE07)))
  local pg0,pg1,pg2=rb(0xEE02),rb(0xEE03),rb(0xEE04)
  f:write(string.format("u_page %02X %02X %02X %02X mpgsel %02X %02X %02X %02X\n",
    pg0,pg1,pg2,rb(0xEE05), rb(0xFE30),rb(0xFE31),rb(0xFE32),rb(0xFE33)))
  iosp:write_u8(0x82,pg0); iosp:write_u8(0xA2,pg1); iosp:write_u8(0xC2,pg2)
  f:write(string.format("sh=%s @112=%02X %02X\n",
    tostring(rb(0x0112)==0xD5 and rb(0x0113)==0xD9), rb(0x0112), rb(0x0113)))
  f:close()
  manager.machine:exit()
end)

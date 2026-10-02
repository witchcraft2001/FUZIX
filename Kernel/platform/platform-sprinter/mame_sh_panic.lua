-- Dump panic deathcry after sh call0 path.
local OUTDIR="/Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/mame_out"
local PANIC=0xFE00
local DBG=0xFE45
local NULLH=0xFE22
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<14.0 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local iosp=cpu.spaces["io"]
  local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  os.execute("mkdir -p "..OUTDIR)
  local f=assert(io.open(OUTDIR.."/sh_panic.txt","w"))
  local pc,sp=st["PC"].value, st["SP"].value
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s\n", t, pc, sp, tostring(st["HALT"].value)))
  f:write(string.format("nullh=%02X callno=%02X insys=%02X u_error=%04X\n",
    rb(NULLH), rb(0xEE07), rb(0xEE06), rw(0xEE08)))
  local pp=rw(PANIC)
  f:write(string.format("panic_ptr=%04X bytes=", pp))
  for i=0,3 do f:write(string.format("%02X ", rb(PANIC+2+i))) end
  f:write("\n")
  if pp ~= 0 then
    local s={}
    for i=0,47 do
      local c=rb(pp+i)
      if c==0 then break end
      if c>=32 and c<127 then s[#s+1]=string.char(c) else s[#s+1]=string.format("\\x%02X",c) end
    end
    f:write("panic_str="..table.concat(s).."\n")
  end
  local pg0,pg1,pg2=rb(0xEE02),rb(0xEE03),rb(0xEE04)
  f:write(string.format("u_page %02X %02X %02X\n", pg0,pg1,pg2))
  if pg0>=8 and pg0<0x48 then
    iosp:write_u8(0x82,pg0); iosp:write_u8(0xA2,pg1); iosp:write_u8(0xC2,pg2)
    f:write(string.format("sh=%s vec0=%02X%02X%02X\n",
      tostring(rb(0x112)==0xD5 and rb(0x113)==0xD9), rb(0),rb(1),rb(2)))
  end
  f:write("dbg=")
  for i=0,22 do f:write(string.format("%02X ", rb(DBG+i))) end
  f:write("\n")
  f:close()
  manager.machine:exit()
end)

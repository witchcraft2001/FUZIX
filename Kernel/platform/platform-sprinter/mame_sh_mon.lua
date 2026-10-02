-- Decode plt_monitor death frame (dbg[0..15] layout from sprinter.s).
-- Refresh from fuzix.map after every link.
local OUTDIR=os.getenv("FUZIX_MAME_OUT") or "/Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/mame_out"
local DBG=0xFEA2
local PANIC=0xFE55
local PANICB=0xFE57
local NULLH=0xFE77
local UD=0xEE00
local KP=0xFE4D
local FAIL=0xFE7C
local DONE=0xFE80
local COUNT=0xFE82
local DEX=0xFE74
local SEEN=0xFE9D
local NOEI=0xFE73
local ISP=0xFEA0
local EXP=0xFE9E
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<45.0 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local iosp=cpu.spaces["io"]
  local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  local f=assert(io.open(OUTDIR.."/sh_mon.txt","w"))
  local pc,sp=st["PC"].value, st["SP"].value
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s IFF=%s\n",
    t, pc, sp, tostring(st["HALT"].value), tostring(st["IFF1"] and st["IFF1"].value or "?")))
  f:write(string.format("fail=%02X done=%04X count=%04X doexec=%02X seen=%02X noei=%02X\n",
    rb(FAIL), rw(DONE), rw(COUNT), rb(DEX), rb(SEEN), rb(NOEI)))
  f:write(string.format("expect=%04X doexec_isp=%04X\n", rw(EXP), rw(ISP)))
  f:write(string.format("udata callno=%02X insys=%02X err=%04X page %02X %02X %02X %02X isp=%04X break=%04X\n",
    rb(UD+7), rb(UD+6), rw(UD+0x0C),
    rb(UD+2), rb(UD+3), rb(UD+4), rb(UD+5),
    rw(UD+26), rw(UD+0x1E)))
  f:write(string.format("nullh=%02X panic_ptr=%04X panic_bytes=%02X %02X %02X %02X\n",
    rb(NULLH), rw(PANIC), rb(PANICB),rb(PANICB+1),rb(PANICB+2),rb(PANICB+3)))
  local pp=rw(PANIC)
  if pp ~= 0 then
    local s={}
    for i=0,63 do
      local c=rb(pp+i)
      if c==0 then break end
      if c>=32 and c<127 then s[#s+1]=string.char(c) else s[#s+1]=string.format("\\x%02X",c) end
    end
    f:write("panic_str="..table.concat(s).."\n")
  end
  f:write("dbg=")
  for i=0,15 do f:write(string.format("%02X ", rb(DBG+i))) end
  f:write("\n")
  local ra=rw(DBG)
  local pptr=rw(DBG+2)
  f:write(string.format("frame: ra=%04X panic=%04X callno=%02X insys=%02X up=%02X%02X%02X mp=%02X%02X%02X err=%04X sp=%02X%02X\n",
    ra, pptr, rb(DBG+4), rb(DBG+5),
    rb(DBG+6),rb(DBG+7),rb(DBG+8),
    rb(DBG+9),rb(DBG+10),rb(DBG+11),
    rw(DBG+12), rb(DBG+14), rb(DBG+15)))
  if pp==0 and pptr~=0 then
    local s={}
    for i=0,63 do
      local c=rb(pptr+i)
      if c==0 then break end
      if c>=32 and c<127 then s[#s+1]=string.char(c) else s[#s+1]=string.format("\\x%02X",c) end
    end
    f:write("frame_panic_str="..table.concat(s).."\n")
  end
  f:write(string.format("kp %02X %02X %02X\n", rb(KP), rb(KP+1), rb(KP+2)))
  -- Map kernel common pages to decode RA
  iosp:write_u8(0x82,rb(KP)); iosp:write_u8(0xA2,rb(KP+1)); iosp:write_u8(0xC2,rb(KP+2))
  f:write(string.format("ra_bytes@%04X=", ra))
  for i=-4,12 do f:write(string.format("%02X ", rb((ra+i)&0xFFFF))) end
  f:write("\n")
  -- Also try CODE1/2/3 known pages if RA in low/mid
  if ra < 0x4000 then
    iosp:write_u8(0x82, 0x48)
    f:write(string.format("CODE1@%04X=", ra))
    for i=-4,12 do f:write(string.format("%02X ", rb((ra+i)&0xFFFF))) end
    f:write("\n")
  elseif ra < 0x8000 then
    iosp:write_u8(0xA2, 0x4C)
    f:write(string.format("CODE2@%04X=", ra))
    for i=-4,12 do f:write(string.format("%02X ", rb((ra+i)&0xFFFF))) end
    f:write("\n")
  elseif ra < 0xC000 then
    iosp:write_u8(0xC2, 0x4D)
    f:write(string.format("CODE3@%04X=", ra))
    for i=-4,12 do f:write(string.format("%02X ", rb((ra+i)&0xFFFF))) end
    f:write("\n")
  end
  local pg0,pg1=rb(DBG+6),rb(DBG+7)
  if pg0>=8 and pg0<0x50 then
    iosp:write_u8(0x82,pg0)
    if pg1>=8 and pg1<0x50 then iosp:write_u8(0xA2,pg1) end
    f:write(string.format("sh @112=%02X%02X @57FA=%02X%02X%02X%02X vec0=%02X%02X%02X\n",
      rb(0x112),rb(0x113), rb(0x57FA),rb(0x57FB),rb(0x57FC),rb(0x57FD),
      rb(0),rb(1),rb(2)))
  end
  f:close()
  manager.machine:exit()
end)

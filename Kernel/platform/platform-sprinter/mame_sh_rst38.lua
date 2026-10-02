-- RST38 death after sh: dump rst38_* latches.
local OUTDIR="/Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/mame_out"
local RST=0xFE07
local DBG=0xFE46
local MPGSEL=0xFDF4
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<16.0 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local iosp=cpu.spaces["io"]
  local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  os.execute("mkdir -p "..OUTDIR)
  local f=assert(io.open(OUTDIR.."/sh_rst38.txt","w"))
  local pc,sp=st["PC"].value, st["SP"].value
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s I=%02X\n",
    t, pc, sp, tostring(st["HALT"].value), st["I"] and st["I"].value or -1))
  f:write(string.format("rst38 count=%02X ret=%04X spl=%04X insys=%02X callno=%02X\n",
    rb(RST), rw(RST+3), rw(RST+1), rb(RST+5), rb(RST+6)))
  f:write(string.format("rst38 up %02X %02X %02X mp %02X %02X %02X\n",
    rb(RST+8),rb(RST+9),rb(RST+10), rb(RST+11),rb(RST+12),rb(RST+13)))
  f:write(string.format("udata callno=%02X insys=%02X page %02X %02X %02X err=%04X break=%04X isp=%04X\n",
    rb(0xEE07),rb(0xEE06), rb(0xEE02),rb(0xEE03),rb(0xEE04),
    rw(0xEE0C), rw(0xEE1E), rw(0xEE1A)))
  f:write(string.format("mpgsel %02X %02X %02X %02X\n",
    rb(MPGSEL),rb(MPGSEL+1),rb(MPGSEL+2),rb(MPGSEL+3)))
  local ret=rw(RST+3)
  local spl=rw(RST+1)
  -- kernel map for ret bytes
  iosp:write_u8(0x82,0x48); iosp:write_u8(0xA2,0x4E); iosp:write_u8(0xC2,0x4F)
  f:write(string.format("ret_bytes@%04X (kernel map)=", ret))
  for i=-2,10 do f:write(string.format("%02X ", rb((ret+i)&0xFFFF))) end
  f:write("\n")
  -- user map for ret bytes
  local u0,u1,u2=rb(0xEE02),rb(0xEE03),rb(0xEE04)
  if u0 < 8 then u0,u1,u2=rb(MPGSEL),rb(MPGSEL+1),rb(MPGSEL+2) end
  if u0 >= 8 and u0 < 0x48 then
    iosp:write_u8(0x82,u0); iosp:write_u8(0xA2,u1); iosp:write_u8(0xC2,u2)
    f:write(string.format("ret_bytes@%04X (user %02X)=", ret, u0))
    for i=-2,10 do f:write(string.format("%02X ", rb((ret+i)&0xFFFF))) end
    f:write("\n")
    f:write(string.format("sh=%s vec0=%02X%02X%02X @112=%02X%02X @0038=%02X%02X%02X\n",
      tostring(rb(0x112)==0xD5 and rb(0x113)==0xD9),
      rb(0),rb(1),rb(2), rb(0x112),rb(0x113), rb(0x38),rb(0x39),rb(0x3A)))
  end
  if spl ~= 0 then
    f:write("stack@spl=")
    for i=0,15 do f:write(string.format("%04X ", rw((spl+i*2)&0xFFFF))) end
    f:write("\n")
  end
  f:write("dbg=")
  for i=0,15 do f:write(string.format("%02X ", rb(DBG+i))) end
  f:write("\n")
  f:close()
  manager.machine:exit()
end)

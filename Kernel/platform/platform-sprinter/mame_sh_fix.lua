-- After load-time CD 00 00→CD 00 01 patch: expect sh past brk, dbg14=DE.
local OUTDIR="/Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/mame_out"
local DBG=0xFE82
local NULLH=0xFE5F
local MPGSEL=0xFE30
local DOESEEN=0xFE7D
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
  local f=assert(io.open(OUTDIR.."/sh_fix.txt","w"))
  local pc,sp=st["PC"].value, st["SP"].value
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s IFF1=%s\n",
    t, pc, sp, tostring(st["HALT"].value), tostring(st["IFF1"] and st["IFF1"].value)))
  f:write(string.format("callno=%02X insys=%02X err=%04X page %02X %02X %02X break=%04X isp=%04X\n",
    rb(0xEE07), rb(0xEE06), rw(0xEE0C),
    rb(0xEE02), rb(0xEE03), rb(0xEE04),
    rw(0xEE1E), rw(0xEE1A)))
  f:write(string.format("nullh=%02X mpgsel %02X %02X %02X doexec_seen=%02X\n",
    rb(NULLH), rb(MPGSEL),rb(MPGSEL+1),rb(MPGSEL+2), rb(DOESEEN)))
  f:write("dbg=")
  for i=0,15 do f:write(string.format("%02X ", rb(DBG+i))) end
  f:write("\n")
  f:write(string.format("dbg14=%02X (want DE=patched)\n", rb(DBG+14)))
  local pg0,pg1,pg2=rb(0xEE02),rb(0xEE03),rb(0xEE04)
  if pg0 < 8 or pg0 >= 0x48 then
    pg0,pg1,pg2 = rb(MPGSEL),rb(MPGSEL+1),rb(MPGSEL+2)
  end
  if pg0 >= 8 and pg0 < 0x48 then
    iosp:write_u8(0x82,pg0); iosp:write_u8(0xA2,pg1); iosp:write_u8(0xC2,pg2)
    f:write(string.format("mapped %02X %02X %02X sh=%s @112=%02X%02X\n",
      pg0,pg1,pg2,
      tostring(rb(0x112)==0xD5 and rb(0x113)==0xD9),
      rb(0x112),rb(0x113)))
    f:write(string.format("vec0=%02X%02X%02X stub100=%02X%02X%02X syscall@4DAB=%02X %02X %02X %02X\n",
      rb(0),rb(1),rb(2), rb(0x100),rb(0x101),rb(0x102),
      rb(0x4DAB),rb(0x4DAC),rb(0x4DAD),rb(0x4DAE)))
  end
  if pc >= 0xF100 and pc < 0xF300 then
    f:write("NOTE: PC in common stub/hang region\n")
  elseif sp > 0xE000 then
    f:write("NOTE: SP looks like user/common stack (good)\n")
  elseif sp < 0x4000 then
    f:write("NOTE: SP corrupt in low memory\n")
  end
  f:write(string.format("pc_bytes=%02X %02X %02X %02X\n", rb(pc),rb(pc+1),rb(pc+2),rb(pc+3)))
  f:close()
  manager.machine:exit()
end)

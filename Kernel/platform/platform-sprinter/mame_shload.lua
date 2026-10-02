-- After rargs u_sysio fix: expect /bin/sh load (not stage 0x97).
local OUTDIR="/Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/mame_out"
local FAIL=0xFE64
local DBG=0xFE82
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
  local f=assert(io.open(OUTDIR.."/shload.txt","w"))
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s\n", t, st["PC"].value, st["SP"].value, tostring(st["HALT"] and st["HALT"].value or "?")))
  f:write(string.format("callno=%02X err=%04X\n", rb(0xEE07), rw(0xEE0C)))
  f:write(string.format("fail_stage=%02X fail_err=%04X\n", rb(FAIL), rw(FAIL+1)))
  f:write("dbg=")
  for i=0,15 do f:write(string.format("%02X ", rb(DBG+i))) end
  f:write("\n")
  local pg0,pg1,pg2=rb(0xEE02),rb(0xEE03),rb(0xEE04)
  f:write(string.format("u_page=%02X %02X %02X break=%04X\n", pg0,pg1,pg2, rw(0xEE10)))
  -- Map user pages to dump PROGLOAD+0x12 and argv / stage
  iosp:write_u8(0x82,pg0); iosp:write_u8(0xA2,pg1); iosp:write_u8(0xC2,pg2)
  f:write(string.format("stage=%02X @112=%02X%02X @4DAB=%02X%02X%02X%02X\n",
    rb(0x1D4), rb(0x112), rb(0x113),
    rb(0x4DAB), rb(0x4DAC), rb(0x4DAD), rb(0x4DAE)))
  f:write(string.format("vec0=%02X%02X%02X dbg14=%02X\n", rb(0), rb(1), rb(2), rb(DBG+14)))
  f:close()
  manager.machine:exit()
end)

-- Dump execve failure latches after sprinit stage 0x97.
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
  local f=assert(io.open(OUTDIR.."/execfail.txt","w"))
  f:write(string.format("t=%.2f PC=%04X SP=%04X\n", t, st["PC"].value, st["SP"].value))
  f:write(string.format("callno=%02X err=%04X\n", rb(0xEE07), rw(0xEE0C)))
  -- exec_diag is 8 bytes at FAIL; equ aliases overlap
  f:write("exec_diag=")
  for i=0,15 do f:write(string.format("%02X ", rb(FAIL+i))) end
  f:write("\n")
  f:write(string.format("fail_stage=%02X fail_err=%04X fail_done=%04X fail_count=%04X\n",
    rb(FAIL), rw(FAIL+1), rw(FAIL+4), rw(FAIL+6)))
  f:write("dbg=")
  for i=0,15 do f:write(string.format("%02X ", rb(DBG+i))) end
  f:write("\n")
  local pg0,pg1,pg2=rb(0xEE02),rb(0xEE03),rb(0xEE04)
  iosp:write_u8(0x82,pg0); iosp:write_u8(0xA2,pg1); iosp:write_u8(0xC2,pg2)
  f:write(string.format("stage=%02X @1C6=%s\n", rb(0x1D4),
    tostring(rb(0x1C6)==0x2F and rb(0x1C7)==0x62))) -- /b
  f:close()
  manager.machine:exit()
end)

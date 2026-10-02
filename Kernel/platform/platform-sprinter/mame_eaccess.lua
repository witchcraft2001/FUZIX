-- Boot and dump as soon as fail_stage becomes non-zero / or after 8s
local OUTDIR="/Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/mame_out"
local FAIL=0xFE64
local DBG=0xFE82
local dumped=false
local last=0
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped then return end
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local iosp=cpu.spaces["io"]
  local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  local fs=rb(FAIL)
  -- dump when fail_stage set or t>=10
  if not ((fs~=0 and fs~=last and fs<0xA0) or t>=10.0) then
    last=fs
    return
  end
  dumped=true
  os.execute("mkdir -p "..OUTDIR)
  local f=assert(io.open(OUTDIR.."/eaccess.txt","w"))
  f:write(string.format("t=%.2f PC=%04X SP=%04X fail=%02X\n", t, st["PC"].value, st["SP"].value, fs))
  f:write(string.format("err=%04X mode_latch via dbg=\n", rw(FAIL+1)))
  f:write("dbg=")
  for i=0,15 do f:write(string.format("%02X ", rb(DBG+i))) end
  f:write("\n")
  -- i_open latches in dbg from filesys: dbg[10]=0x33, [11..14]=dev/ino
  f:write(string.format("iopen_mark=%02X dev=%02X%02X ino=%02X%02X\n",
    rb(DBG+10), rb(DBG+11), rb(DBG+12), rb(DBG+13), rb(DBG+14)))
  local pg0,pg1,pg2=rb(0xEE02),rb(0xEE03),rb(0xEE04)
  iosp:write_u8(0x82,pg0); iosp:write_u8(0xA2,pg1); iosp:write_u8(0xC2,pg2)
  f:write(string.format("u_page=%02X%02X%02X @112=%02X%02X stage@1D4=%02X\n",
    pg0,pg1,pg2, rb(0x112),rb(0x113), rb(0x1D4)))
  f:close()
  manager.machine:exit()
end)

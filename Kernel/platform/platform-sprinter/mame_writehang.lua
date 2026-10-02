local OUTDIR="/Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/mame_out"
local DBG=0xFE82
local RST38=0xFE43
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<12.0 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local iosp=cpu.spaces["io"]
  local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  os.execute("mkdir -p "..OUTDIR)
  local f=assert(io.open(OUTDIR.."/writehang.txt","w"))
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s IFF=%s\n",
    t, st["PC"].value, st["SP"].value,
    tostring(st["HALT"] and st["HALT"].value or "?"),
    tostring(st["IFF1"] and st["IFF1"].value or "?")))
  f:write(string.format("callno=%02X err=%04X insys=%02X\n", rb(0xEE07), rw(0xEE0C), rb(0xEE06)))
  f:write(string.format("u_top=%04X u_break=%04X u_base=%04X u_count=%04X u_done=%04X\n",
    rw(0xEE1C), rw(0xEE1E), rw(0xEE62), rw(0xEE64), rw(0xEE18)))
  -- U_BASE is offset 98 = 0x62 from udata EE00 → EE62. U_COUNT?
  -- Check kernel.def for U_COUNT U_DONE
  f:write(string.format("rst38=%02X ret=%04X sp_latch=%04X\n",
    rb(RST38), rw(RST38+3), rw(RST38+1)))
  f:write(string.format("rw_stage=%02X va_stage=%02X\n", rb(0xFE6C), rb(0xFE6C)))
  f:write("dbg=")
  for i=0,15 do f:write(string.format("%02X ", rb(DBG+i))) end
  f:write("\n")
  local pg0=rb(0xEE02)
  iosp:write_u8(0x82,pg0)
  f:write(string.format("@112=%02X%02X @126=%02X%02X\n", rb(0x112),rb(0x113), rb(0x126),rb(0x127)))
  f:write(string.format("code@PC="))
  local pc=st["PC"].value
  for i=0,7 do f:write(string.format("%02X ", rb(pc+i))) end
  f:write("\n")
  f:close()
  manager.machine:exit()
end)


local OUT="/Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/mame_out/stage.txt"
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<16 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local io=cpu.spaces["io"]
  local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local f=assert(io.open(OUT,"w"))
  local pg0,pg1,pg2=rb(0xEE02),rb(0xEE03),rb(0xEE04)
  f:write(string.format("PC=%04X SP=%04X page %02X %02X %02X callno=%02X err=%04X break=%04X\n",
    st["PC"].value, st["SP"].value, pg0,pg1,pg2, rb(0xEE07), rb(0xEE0C)+256*rb(0xEE0D), rb(0xEE1E)+256*rb(0xEE1F)))
  if pg0>=8 and pg0<0x48 then
    io:write_u8(0x82,pg0); io:write_u8(0xA2,pg1); io:write_u8(0xC2,pg2)
    f:write(string.format("stage=%02X wr=%02X%02X @112=%02X%02X @188=%02X%02X%02X%02X\n",
      rb(0x1D4), rb(0x1D5),rb(0x1D6), rb(0x112),rb(0x113),
      rb(0x188),rb(0x189),rb(0x18A),rb(0x18B)))
    -- check exec fail markers in dbg
  end
  f:write(string.format("exec_fail_stage=%02X\n", rb(0xFE82))) -- may be wrong
  f:close()
  manager.machine:exit()
end)

-- sprinit stage / exec outcome
local OUTDIR="/Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/mame_out"
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
  local f=assert(io.open(OUTDIR.."/stage2.txt","w"))
  local pc,sp=st["PC"].value, st["SP"].value
  local pg0,pg1,pg2=rb(0xEE02),rb(0xEE03),rb(0xEE04)
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s\n",
    t, pc, sp, tostring(st["HALT"].value)))
  f:write(string.format("callno=%02X insys=%02X err=%04X page %02X %02X %02X break=%04X\n",
    rb(0xEE07), rb(0xEE06), rw(0xEE0C), pg0,pg1,pg2, rw(0xEE1E)))
  if pg0>=8 and pg0<0x48 then
    iosp:write_u8(0x82,pg0); iosp:write_u8(0xA2,pg1); iosp:write_u8(0xC2,pg2)
    f:write(string.format("stage=%02X wr=%04X @112=%02X%02X\n",
      rb(0x1D4), rw(0x1D5), rb(0x112), rb(0x113)))
    f:write(string.format("syscall@4DAB=%02X %02X %02X %02X vec0=%02X%02X%02X\n",
      rb(0x4DAB),rb(0x4DAC),rb(0x4DAD),rb(0x4DAE), rb(0),rb(1),rb(2)))
  end
  f:close()
  manager.machine:exit()
end)

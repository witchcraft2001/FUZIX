-- Auto-refreshed from Kernel/fuzix.map + sprinit_raw layout
local OUTDIR = os.getenv("FUZIX_MAME_OUT") or "."
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<5.5 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local iosp=cpu.spaces["io"]
  local st=cpu.state
  local f=assert(io.open(OUTDIR.."/write2.txt","w"))
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  f:write(string.format("PC=%04X SP=%04X HALT=%s\n", st["PC"].value, st["SP"].value, tostring(st["HALT"].value)))
  f:write(string.format("rst38 count=%02X ret=%04X sp=%04X insys=%02X callno=%02X\n",
    rb(0xFE43), rw(0xFE46), rw(0xFE44), rb(0xFE48), rb(0xFE49)))
  f:write(string.format("mpgsel_cache=%02X %02X %02X %02X kp=%02X %02X %02X %02X\n",
    rb(0xFE30), rb(0xFE31), rb(0xFE32), rb(0xFE33),
    rb(0xFE35), rb(0xFE36), rb(0xFE37), rb(0xFE38)))
  f:write(string.format("udata page=%02X %02X %02X %02X argn=%04X %04X %04X err=%04X retval=%04X done=%04X\n",
    rb(0xEE02), rb(0xEE03), rb(0xEE04), rb(0xEE05),
    rw(0xEE12), rw(0xEE14), rw(0xEE16), rw(0xEE0C), rw(0xEE0A), rw(0xEE9F)))
  f:write(string.format("exit_no=%02X exit_err=%04X chlink=%02X/%04X\n",
    rb(0xFED5), rw(0xFED6), rb(0xFE9C), rw(0xFEA3)))
  f:write(string.format("u_files=%02X %02X %02X\n", rb(0xEE7D), rb(0xEE7E), rb(0xEE7F)))
  f:write(string.format("rw_stage=%02X dbg0=%02X dbg8=%02X dbg9=%02X dbg11=%02X\n",
    rb(0xFE94), rb(0xFEFC), rb(0xFF04), rb(0xFF05), rb(0xFF07)))
  iosp:write_u8(0x82, 0x44); iosp:write_u8(0xA2, 0x45); iosp:write_u8(0xC2, 0x46)
  f:write(string.format("USER stage=%02X wr=%04X spin=%02X\n", rb(0x0173), rw(0x0176), rb(0x0178)))
  f:write("msg=")
  for i=0,24 do
    local c=rb(0x015B+i)
    if c>=32 and c<127 then f:write(string.char(c)) else f:write(".") end
  end
  f:write("\n")
  iosp:write_u8(0x82, 0x48); iosp:write_u8(0xA2, 0x49); iosp:write_u8(0xC2, 0x4A)
  f:write(string.format("oft0 ino=%04X acc=%02X refs=%02X\n",
    rw(0x156A), rb(0x156C), rb(0x156D)))
  f:close()
end)

-- One-shot dump (no live remapping during the run — that stalls the guest).
-- Remap only once at dump time to read user low page for /bin/sh signature.
-- Addresses from Kernel/fuzix.map COMMONDATA (rebuild shifts them!).
local OUTDIR="/Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/mame_out"
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<8.0 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local iosp=cpu.spaces["io"]
  local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  os.execute("mkdir -p "..OUTDIR)
  local f=assert(io.open(OUTDIR.."/hangfix.txt","w"))
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s IFF1=%s IM=%s I=%02X\n",
    t, st["PC"].value, st["SP"].value, tostring(st["HALT"].value),
    tostring(st["IFF1"] and st["IFF1"].value),
    tostring(st["IM"] and st["IM"].value),
    st["I"] and st["I"].value or 0))
  -- udata @ EE00: u_page+2, u_insys+6, u_callno+7 (z80 banked layout)
  f:write(string.format("rw=%02X panic=%04X bytes=%02X%02X%02X%02X callno=%02X insys=%02X\n",
    rb(0xFE7F), rw(0xFE49), rb(0xFE4B),rb(0xFE4C),rb(0xFE4D),rb(0xFE4E),
    rb(0xEE07), rb(0xEE06)))
  f:write(string.format("rst38=%02X nullh=%02X nmi=%02X null_sp=%04X/%04X noei=%02X intd=%02X\n",
    rb(0xFE4F), rb(0xFE6A), rb(0xFE69), rw(0xFE6B), rw(0xFE6D), rb(0xFE67), rb(0xFE66)))
  f:write(string.format("doexec arm=%02X seen=%02X expect=%04X isp=%04X u=%02X%02X%02X%02X m=%02X%02X%02X\n",
    rb(0xFECE), rb(0xFECF), rw(0xFED2), rw(0xFED4),
    rb(0xFED6),rb(0xFED7),rb(0xFED8),rb(0xFED9),
    rb(0xFEDA),rb(0xFEDB),rb(0xFEDC)))
  f:write(string.format("stage@01D4=%02X path@01C6=%02X%02X%02X%02X\n",
    rb(0x01D4), rb(0x01C6), rb(0x01C7), rb(0x01C8), rb(0x01C9)))
  local pg0,pg1,pg2,pg3=rb(0xEE02),rb(0xEE03),rb(0xEE04),rb(0xEE05)
  f:write(string.format("u_page %02X %02X %02X %02X mpgsel %02X %02X %02X %02X kern %02X %02X %02X %02X\n",
    pg0,pg1,pg2,pg3, rb(0xFE3C),rb(0xFE3D),rb(0xFE3E),rb(0xFE3F),
    rb(0xFE41),rb(0xFE42),rb(0xFE43),rb(0xFE44)))
  local pc=st["PC"].value
  local sp=st["SP"].value
  f:write(string.format("pc_bytes=%02X %02X %02X %02X  sp_words=%04X %04X %04X %04X\n",
    rb(pc), rb(pc+1), rb(pc+2), rb(pc+3),
    rw(sp), rw(sp+2), rw(sp+4), rw(sp+6)))
  -- Map user page0 once to check /bin/sh signature (do not leave live remapping on).
  iosp:write_u8(0x82,pg0); iosp:write_u8(0xA2,pg1); iosp:write_u8(0xC2,pg2)
  f:write(string.format("sh=%s @112=%02X %02X stage_live=%02X\n",
    tostring(rb(0x0112)==0xD5 and rb(0x0113)==0xD9), rb(0x0112), rb(0x0113), rb(0x01D4)))
  f:close()
  manager.machine:exit()
end)

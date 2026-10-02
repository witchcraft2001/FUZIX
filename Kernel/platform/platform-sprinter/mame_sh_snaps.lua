-- Multi-snapshot WITHOUT remapping (remap stalls/corrupts the guest).
-- sh signature only checked on the final snapshot.
local OUTDIR="/Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/mame_out"
local times={3.0,4.0,5.0,6.0,7.0,8.0}
local done={}
local n=0
for i=1,#times do done[i]=false end

emu.register_frame(function()
  local t=manager.machine.time:as_double()
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local iosp=cpu.spaces["io"]
  local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end

  for i,tt in ipairs(times) do
    if (not done[i]) and t>=tt then
      done[i]=true
      n=n+1
      os.execute("mkdir -p "..OUTDIR)
      local f=assert(io.open(string.format("%s/snap_t%.0f.txt", OUTDIR, tt),"w"))
      local pc=st["PC"].value
      local sp=st["SP"].value
      f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s IFF1=%s\n",
        t, pc, sp, tostring(st["HALT"].value),
        tostring(st["IFF1"] and st["IFF1"].value)))
      f:write(string.format("callno=%02X insys=%02X intd=%02X noei=%02X rw=%02X nullh=%02X rst38=%02X\n",
        rb(0xEE07), rb(0xEE06), rb(0xFE66), rb(0xFE67), rb(0xFE7F),
        rb(0xFE6A), rb(0xFE4F)))
      f:write(string.format("doexec arm=%02X seen=%02X expect=%04X isp=%04X u=%02X%02X%02X%02X m=%02X%02X%02X\n",
        rb(0xFECE), rb(0xFECF), rw(0xFED2), rw(0xFED4),
        rb(0xFED6),rb(0xFED7),rb(0xFED8),rb(0xFED9),
        rb(0xFEDA),rb(0xFEDB),rb(0xFEDC)))
      local pg0,pg1,pg2,pg3=rb(0xEE02),rb(0xEE03),rb(0xEE04),rb(0xEE05)
      f:write(string.format("u_page %02X %02X %02X %02X mpgsel %02X %02X %02X %02X kern %02X %02X %02X %02X\n",
        pg0,pg1,pg2,pg3, rb(0xFE3C),rb(0xFE3D),rb(0xFE3E),rb(0xFE3F),
        rb(0xFE41),rb(0xFE42),rb(0xFE43),rb(0xFE44)))
      f:write(string.format("pc_bytes=%02X %02X %02X %02X  sp_words=%04X %04X %04X %04X\n",
        rb(pc), rb(pc+1), rb(pc+2), rb(pc+3),
        rw(sp), rw(sp+2), rw(sp+4), rw(sp+6)))
      if i==#times then
        iosp:write_u8(0x82,pg0); iosp:write_u8(0xA2,pg1); iosp:write_u8(0xC2,pg2)
        f:write(string.format("sh=%s @112=%02X %02X stage=%02X\n",
          tostring(rb(0x0112)==0xD5 and rb(0x0113)==0xD9),
          rb(0x0112), rb(0x0113), rb(0x01D4)))
        manager.machine:exit()
      end
      f:close()
    end
  end
end)

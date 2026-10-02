-- Fine-grain snapshots, no mid-run remap. Addresses from fuzix.map.
local OUTDIR="/Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/mame_out"
local times={4.0,4.5,5.0,6.0,7.0,8.0,10.0}
local done={}
for i=1,#times do done[i]=false end
local n=0

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
      local tag=string.format("%s", tt)
      local f=assert(io.open(string.format("%s/fine_t%s.txt", OUTDIR, tag),"w"))
      local pc=st["PC"].value
      local sp=st["SP"].value
      f:write(string.format("t=%.2f PC=%04X SP=%04X IFF1=%s HALT=%s\n",
        t, pc, sp, tostring(st["IFF1"] and st["IFF1"].value), tostring(st["HALT"].value)))
      f:write(string.format("callno=%02X insys=%02X intd=%02X rw=%02X nullh=%02X stage=%02X\n",
        rb(0xEE07), rb(0xEE06), rb(0xFE77), rb(0xFE91), rb(0xFE7C), rb(0xFE81)))
      f:write(string.format("seen=%02X arm=%02X expect=%04X isp=%04X mpgsel %02X %02X %02X %02X\n",
        rb(0xFEC2), rb(0xFEC1), rw(0xFEC5), rw(0xFEC7),
        rb(0xFE4D),rb(0xFE4E),rb(0xFE4F),rb(0xFE50)))
      f:write(string.format("pc_bytes=%02X %02X %02X %02X sp0=%04X vec0=%02X%02X%02X\n",
        rb(pc),rb(pc+1),rb(pc+2),rb(pc+3), rw(sp), rb(0),rb(1),rb(2)))
      if tt>=10.0 then
        local pg0,pg1,pg2=rb(0xEE02),rb(0xEE03),rb(0xEE04)
        iosp:write_u8(0x82,pg0); iosp:write_u8(0xA2,pg1); iosp:write_u8(0xC2,pg2)
        f:write(string.format("sh=%s @112=%02X %02X vec0u=%02X%02X%02X\n",
          tostring(rb(0x0112)==0xD5 and rb(0x0113)==0xD9), rb(0x0112), rb(0x0113),
          rb(0),rb(1),rb(2)))
        manager.machine:exit()
      end
      f:close()
    end
  end
end)

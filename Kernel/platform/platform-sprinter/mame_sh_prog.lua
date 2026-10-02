-- Post-sh progress probe after ret-on-no-panic restore.
local OUTDIR="/Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/mame_out"
local DBG=0xFE46
local PANIC=0xFE01
local NULLH=0xFE23
local MPGSEL=0xFDF4
local DOESEEN=0xFE41
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
  local f=assert(io.open(OUTDIR.."/sh_prog.txt","w"))
  local pc,sp=st["PC"].value, st["SP"].value
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s IFF1=%s\n",
    t, pc, sp, tostring(st["HALT"].value), tostring(st["IFF1"] and st["IFF1"].value)))
  f:write(string.format("callno=%02X insys=%02X err=%04X page %02X %02X %02X break=%04X isp=%04X\n",
    rb(0xEE07), rb(0xEE06), rw(0xEE0C),
    rb(0xEE02), rb(0xEE03), rb(0xEE04),
    rw(0xEE1E), rw(0xEE1A)))
  f:write(string.format("nullh=%02X panic=%04X mpgsel %02X %02X %02X doexec_seen=%02X\n",
    rb(NULLH), rw(PANIC), rb(MPGSEL),rb(MPGSEL+1),rb(MPGSEL+2), rb(DOESEEN)))
  f:write("dbg=")
  for i=0,15 do f:write(string.format("%02X ", rb(DBG+i))) end
  f:write("\n")
  local pg0,pg1,pg2=rb(0xEE02),rb(0xEE03),rb(0xEE04)
  if pg0 < 8 or pg0 >= 0x48 then
    pg0,pg1,pg2 = rb(MPGSEL),rb(MPGSEL+1),rb(MPGSEL+2)
  end
  if pg0 >= 8 and pg0 < 0x48 then
    iosp:write_u8(0x82,pg0); iosp:write_u8(0xA2,pg1); iosp:write_u8(0xC2,pg2)
    f:write(string.format("mapped %02X %02X %02X sh=%s @112=%02X%02X vec0=%02X%02X%02X\n",
      pg0,pg1,pg2,
      tostring(rb(0x112)==0xD5 and rb(0x113)==0xD9),
      rb(0x112),rb(0x113), rb(0),rb(1),rb(2)))
  end
  local pp=rw(PANIC)
  if pp ~= 0 then
    local s={}
    for i=0,47 do
      local c=rb(pp+i)
      if c==0 then break end
      if c>=32 and c<127 then s[#s+1]=string.char(c) else s[#s+1]="?" end
    end
    f:write("panic_str="..table.concat(s).."\n")
  end
  -- classify PC
  if pc >= 0xF100 and pc < 0xF180 then
    f:write("NOTE: PC in plt_monitor region\n")
  elseif pc < 0x100 then
    f:write("NOTE: PC in low vectors\n")
  elseif pc >= 0x100 and pc < 0xC000 then
    f:write("NOTE: PC in user/banked range\n")
  end
  f:write(string.format("pc_bytes=%02X %02X %02X %02X\n", rb(pc),rb(pc+1),rb(pc+2),rb(pc+3)))
  f:close()
  manager.machine:exit()
end)

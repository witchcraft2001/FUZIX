-- RST38 hang during write: dump latches + sprinit stage.
local OUTDIR="/Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/mame_out"
local DBG=0xFEE8
local RST38=0xFEA9  -- _sprinter_rst38_count
local MPGSEL=0xFE96
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
  local f=assert(io.open(OUTDIR.."/rst38_write.txt","w"))
  local pc,sp=st["PC"].value, st["SP"].value
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s IFF1=%s I=%02X\n",
    t, pc, sp, tostring(st["HALT"].value),
    tostring(st["IFF1"] and st["IFF1"].value), st["I"] and st["I"].value or -1))
  f:write(string.format("rst38_count=%02X ret=%04X sp_latch=%04X insys=%02X callno=%02X inirq=%02X\n",
    rb(RST38), rw(RST38+3), rw(RST38+1), rb(RST38+5), rb(RST38+6), rb(RST38+7)))
  f:write(string.format("rst38_up %02X %02X %02X mp %02X %02X %02X Ireg=%02X\n",
    rb(RST38+8),rb(RST38+9),rb(RST38+10),
    rb(RST38+11),rb(RST38+12),rb(RST38+13), rb(RST38+14)))
  f:write(string.format("udata insys=%02X callno=%02X u_page %02X %02X %02X\n",
    rb(0xEE06), rb(0xEE07), rb(0xEE02),rb(0xEE03),rb(0xEE04)))
  f:write(string.format("mpgsel %02X %02X %02X %02X\n",
    rb(MPGSEL),rb(MPGSEL+1),rb(MPGSEL+2),rb(MPGSEL+3)))
  -- sprinit stage at 0x1D4 on user pages
  local pg0,pg1,pg2=rb(0xEE02),rb(0xEE03),rb(0xEE04)
  iosp:write_u8(0x82,pg0); iosp:write_u8(0xA2,pg1); iosp:write_u8(0xC2,pg2)
  f:write(string.format("spr_stage=%02X spr_wr=%04X @112=%02X%02X\n",
    rb(0x1D4), rw(0x1D5), rb(0x112), rb(0x113)))
  -- restore kernel WIN0 and dump code at fault PC
  iosp:write_u8(0x82,0x48); iosp:write_u8(0xA2,0x4E); iosp:write_u8(0xC2,0x4F)
  local ret=rw(RST38+3)
  f:write(string.format("fault_pc_bytes@%04X=", ret))
  for i=-4,8 do f:write(string.format("%02X ", rb(ret+i))) end
  f:write("\n")
  f:write(string.format("i_tab@16E6 first16="))
  for i=0,15 do f:write(string.format("%02X ", rb(0x16E6+i))) end
  f:write("\n")
  f:write("dbg=")
  for i=0,23 do f:write(string.format("%02X ", rb(DBG+i))) end
  f:write("\n")
  f:write(string.format("stack@SP="))
  for i=0,15 do f:write(string.format("%04X ", rw(sp+i*2))) end
  f:write("\n")
  f:close()
  manager.machine:exit()
end)

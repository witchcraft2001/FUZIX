-- Dump sh hang focus after null→syscall trampoline.
-- Addresses from fuzix.map (COMMONDATA fit check: dbg@FEDF, nullh@FEA1).
-- Remap user pages ONLY at dump/exit — never live mid-run.
local OUTDIR="/Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/mame_out"
local DBG=0xFEDF
local NULLH=0xFEA1
local MPGSEL=0xFE72
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<10.0 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local iosp=cpu.spaces["io"]
  local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  os.execute("mkdir -p "..OUTDIR)
  local f=assert(io.open(OUTDIR.."/sh_null.txt","w"))
  local pc,sp=st["PC"].value, st["SP"].value
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s IFF1=%s\n",
    t, pc, sp, tostring(st["HALT"].value), tostring(st["IFF1"] and st["IFF1"].value)))
  f:write(string.format("nullh=%02X callno=%02X insys=%02X\n",
    rb(NULLH), rb(0xEE07), rb(0xEE06)))
  local pg0,pg1,pg2=rb(0xEE02),rb(0xEE03),rb(0xEE04)
  f:write(string.format("u_page %02X %02X %02X mpgsel %02X %02X %02X %02X\n",
    pg0,pg1,pg2, rb(MPGSEL),rb(MPGSEL+1),rb(MPGSEL+2),rb(MPGSEL+3)))
  -- Remap user once for inspection of sh image
  iosp:write_u8(0x82,pg0); iosp:write_u8(0xA2,pg1); iosp:write_u8(0xC2,pg2)
  f:write(string.format("sh=%s @112=%02X%02X vec0=%02X%02X%02X stub100=%02X%02X%02X\n",
    tostring(rb(0x112)==0xD5 and rb(0x113)==0xD9), rb(0x112),rb(0x113),
    rb(0),rb(1),rb(2), rb(0x100),rb(0x101),rb(0x102)))
  f:write(string.format("syscall@4DAB=%02X %02X %02X %02X (CD 00 00 D0 = unreloc; trampoline OK)\n",
    rb(0x4DAB),rb(0x4DAC),rb(0x4DAD),rb(0x4DAE)))
  f:write(string.format("sp_words=%04X %04X %04X %04X\n",
    rw(sp),rw(sp+2),rw(sp+4),rw(sp+6)))
  f:write("dbg=")
  for i=0,23 do f:write(string.format("%02X ", rb(DBG+i))) end
  f:write("\n")
  f:write(string.format("dbg15=%02X (want CE=trampoline) dbg16=%02X null_stub@F25D=%02X%02X%02X\n",
    rb(DBG+15), rb(DBG+16), rb(0xF25D),rb(0xF25E),rb(0xF25F)))
  f:write(string.format("pc_bytes=%02X %02X %02X %02X\n", rb(pc),rb(pc+1),rb(pc+2),rb(pc+3)))
  f:close()
  manager.machine:exit()
end)

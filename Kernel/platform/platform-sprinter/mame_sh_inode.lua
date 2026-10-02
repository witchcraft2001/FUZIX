
local OUTDIR=os.getenv("FUZIX_MAME_OUT") or "."
local UD,DBG=0xEE00,65208
local DEX,NOEI,FAIL=65162,65161,65170
local NULLH,R38,R38R,R38SP=65165,65137,65140,65138
local R38UP,R38MP=65145,65148
local KP,MP=65123,65118
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<60 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]; local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  local f=assert(io.open(OUTDIR.."/sh_inode.txt","w"))
  local pc,sp=st["PC"].value,st["SP"].value
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s\n",t,pc,sp,tostring(st["HALT"].value)))
  f:write(string.format("doexec=%02X noei=%02X fail=%02X nullh=%02X rst38=%02X ret=%04X sp=%04X\n",rb(DEX),rb(NOEI),rb(FAIL),rb(NULLH),rb(R38),rw(R38R),rw(R38SP)))
  f:write(string.format("rst38 up %02X %02X %02X mp %02X %02X %02X\n",rb(R38UP),rb(R38UP+1),rb(R38UP+2),rb(R38MP),rb(R38MP+1),rb(R38MP+2)))
  f:write(string.format("callno=%02X insys=%02X err=%04X arg=%04X %04X %04X done=%04X\n",rb(UD+7),rb(UD+6),rw(UD+12),rw(UD+18),rw(UD+20),rw(UD+22),rw(UD+0x9F)))
  f:write(string.format("kp %02X %02X %02X mp %02X %02X %02X\n",rb(KP),rb(KP+1),rb(KP+2),rb(MP),rb(MP+1),rb(MP+2)))
  f:write(string.format("@C000 "))
  for i=0,15 do f:write(string.format("%02X ",rb(0xC000+i))) end
  f:write(string.format("\n@SP "))
  for i=0,23 do f:write(string.format("%02X ",rb(sp+i))) end
  f:write(string.format("\n@EDB1 "))
  for i=0,15 do f:write(string.format("%02X ",rb(0xEDB1+i))) end
  f:write("\n")
  f:close(); manager.machine:exit()
end)

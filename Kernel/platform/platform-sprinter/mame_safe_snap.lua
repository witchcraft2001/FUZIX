local OUTDIR=os.getenv("FUZIX_MAME_OUT") or "."
local UD,DEX,NOEI,R38,R38R=0xEE00,65201,65200,65176,65179
local KP,MP,RWS,DBG,NULLH=65162,65157,65225,65247,65204
local done={}

local function dump(tag)
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]; local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  local f=assert(io.open(OUTDIR.."/"..tag,"w"))
  local pc,sp=st["PC"].value,st["SP"].value
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s\n", manager.machine.time:as_double(),pc,sp,tostring(st["HALT"].value)))
  f:write(string.format("doexec=%02X noei=%02X rst38=%02X ret=%04X nullh=%02X\n",
    rb(DEX),rb(NOEI),rb(R38),rw(R38R),rb(NULLH)))
  f:write(string.format("callno=%02X insys=%02X err=%04X arg=%04X %04X %04X done=%04X\n",
    rb(UD+7),rb(UD+6),rw(UD+12),rw(UD+18),rw(UD+20),rw(UD+22),rw(UD+0x9F)))
  f:write(string.format("kp %02X %02X %02X %02X mp %02X %02X %02X %02X\n",
    rb(KP),rb(KP+1),rb(KP+2),rb(KP+3),rb(MP),rb(MP+1),rb(MP+2),rb(MP+3)))
  f:write(string.format("rw_stage=%02X\n",rb(RWS)))
  f:write("@0 ")
  for i=0,7 do f:write(string.format("%02X ",rb(i))) end
  f:write("\n")
  f:close()
end
emu.register_frame(function()
  local t=manager.machine.time:as_double()

  if not done[4] and t>=4 then done[4]=true; dump(string.format("s%02d.txt",4)) end
  if not done[5] and t>=5 then done[5]=true; dump(string.format("s%02d.txt",5)) end
  if not done[6] and t>=6 then done[6]=true; dump(string.format("s%02d.txt",6)) end
  if not done[7] and t>=7 then done[7]=true; dump(string.format("s%02d.txt",7)) end
  if not done[8] and t>=8 then done[8]=true; dump(string.format("s%02d.txt",8)) end
  if not done[9] and t>=9 then done[9]=true; dump(string.format("s%02d.txt",9)) end
  if not done[10] and t>=10 then done[10]=true; dump(string.format("s%02d.txt",10)) end
  if not done[15] and t>=15 then done[15]=true; dump(string.format("s%02d.txt",15)) end
  if not done[20] and t>=20 then done[20]=true; dump(string.format("s%02d.txt",20)) end
  if not done[30] and t>=30 then done[30]=true; dump(string.format("s%02d.txt",30)) end
  if t>=35 then dump("final.txt"); manager.machine:exit() end
end)


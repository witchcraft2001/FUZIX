-- Auto from fuzix.map: read/C000 bring-up dump
local OUTDIR=os.getenv("FUZIX_MAME_OUT") or "."
local UD=0xEE00
local DEX=65198
local NOEI=65197
local R38=65173
local R38R=65176
local R38SP=65174
local R38IN=65178
local R38CN=65179
local R38MP=65184
local KP=65159
local MP=65154
local RWS=65222
local RWFD=65224
local RWB=65225
local RWC=65227
local RWA=65229
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<60 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]; local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  local f=assert(io.open(OUTDIR.."/read_c000.txt","w"))
  local pc,sp=st["PC"].value,st["SP"].value
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s\n",t,pc,sp,tostring(st["HALT"].value)))
  f:write(string.format("doexec=%02X noei=%02X rst38=%02X ret=%04X sp=%04X insys=%02X r38call=%02X\n",
    rb(DEX),rb(NOEI),rb(R38),rw(R38R),rw(R38SP),rb(R38IN),rb(R38CN)))
  f:write(string.format("rst38 mp %02X %02X %02X\n",rb(R38MP),rb(R38MP+1),rb(R38MP+2)))
  f:write(string.format("callno=%02X insys=%02X err=%04X arg=%04X %04X %04X done=%04X\n",
    rb(UD+7),rb(UD+6),rw(UD+12),rw(UD+18),rw(UD+20),rw(UD+22),rw(UD+0x9F)))
  f:write(string.format("kp %02X %02X %02X mp %02X %02X %02X\n",rb(KP),rb(KP+1),rb(KP+2),rb(MP),rb(MP+1),rb(MP+2)))
  f:write(string.format("rw_stage=%02X fd=%02X base=%04X count=%04X access=%02X\n",
    rb(RWS),rb(RWFD),rw(RWB),rw(RWC),rb(RWA)))
  f:write(string.format("@C000 "))
  for i=0,15 do f:write(string.format("%02X ",rb(0xC000+i))) end
  f:write(string.format("\n@SP "))
  for i=0,31 do f:write(string.format("%02X ",rb(sp+i))) end
  local rsp=rw(R38SP)
  f:write(string.format("\n@rst38_sp=%04X ",rsp))
  for i=0,31 do f:write(string.format("%02X ",rb(rsp+i))) end
  f:write(string.format("\n@EDB1 "))
  for i=0,15 do f:write(string.format("%02X ",rb(0xEDB1+i))) end
  f:write("\n")
  f:close(); manager.machine:exit()
end)


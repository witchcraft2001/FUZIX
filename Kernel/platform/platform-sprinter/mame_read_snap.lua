
local OUTDIR=os.getenv("FUZIX_MAME_OUT") or "."
local UD=0xEE00
local DEX,NOEI=65198,65197
local R38,R38R=65173,65176
local KP,MP=65159,65154
local RWS=65222
local snaps={15,false},{25,false},{35,false},{45,false},{55,false}
local function snap(tag)
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]; local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  local f=assert(io.open(OUTDIR.."/"..tag,"w"))
  local pc,sp=st["PC"].value,st["SP"].value
  f:write(string.format("t tag PC=%04X SP=%04X HALT=%s\n",pc,sp,tostring(st["HALT"].value)))
  f:write(string.format("doexec=%02X noei=%02X rst38=%02X ret=%04X\n",rb(DEX),rb(NOEI),rb(R38),rw(R38R)))
  f:write(string.format("callno=%02X insys=%02X err=%04X arg=%04X %04X %04X done=%04X\n",
    rb(UD+7),rb(UD+6),rw(UD+12),rw(UD+18),rw(UD+20),rw(UD+22),rw(UD+0x9F)))
  f:write(string.format("kp %02X %02X %02X %02X mp %02X %02X %02X %02X\n",
    rb(KP),rb(KP+1),rb(KP+2),rb(KP+3),rb(MP),rb(MP+1),rb(MP+2),rb(MP+3)))
  f:write(string.format("rw_stage=%02X\n",rb(RWS)))
  f:write(string.format("@EE00 "))
  for i=0,31 do f:write(string.format("%02X ",rb(0xEE00+i))) end
  f:write("\n")
  f:close()
end
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  for i,s in ipairs(snaps) do
    if (not s[2]) and t>=s[1] then
      s[2]=true
      snap(string.format("snap_%02d.txt", s[1]))
    end
  end
  if t>=58 then manager.machine:exit() end
end)



local OUTDIR=os.getenv("FUZIX_MAME_OUT") or "."
local UD=0xEE00
local DEX=65198
local NOEI=65197
local R38=65173
local R38R=65176
local KP=65159
local MP=65154
local RWS=65222
local DBG=65244
local PAN=65167
local PANB=65169
local armed=false
local dumped=false
local last_call=-1
local last_alive=0
local function dump(tag)
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]; local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  -- Force kernel common mapping for latch reads
  local iosp=cpu.spaces["io"]
  if iosp then
    iosp:write_u8(0x82, 0x48)
    iosp:write_u8(0xA2, 0x49)
    iosp:write_u8(0xC2, 0x4A)
    iosp:write_u8(0xE2, 0x4B)
  end
  local f=assert(io.open(OUTDIR.."/"..tag,"w"))
  local pc,sp=st["PC"].value,st["SP"].value
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s\n", manager.machine.time:as_double(),pc,sp,tostring(st["HALT"].value)))
  f:write(string.format("doexec=%02X noei=%02X rst38=%02X ret=%04X\n",rb(DEX),rb(NOEI),rb(R38),rw(R38R)))
  f:write(string.format("callno=%02X insys=%02X err=%04X arg=%04X %04X %04X done=%04X\n",
    rb(UD+7),rb(UD+6),rw(UD+12),rw(UD+18),rw(UD+20),rw(UD+22),rw(UD+0x9F)))
  f:write(string.format("kp %02X %02X %02X %02X mp %02X %02X %02X %02X\n",
    rb(KP),rb(KP+1),rb(KP+2),rb(KP+3),rb(MP),rb(MP+1),rb(MP+2),rb(MP+3)))
  f:write(string.format("rw_stage=%02X panic_ptr=%04X\n",rb(RWS),rw(PAN)))
  f:write(string.format("panic_bytes %02X %02X %02X %02X\n",rb(PANB),rb(PANB+1),rb(PANB+2),rb(PANB+3)))
  f:write("dbg ")
  for i=0,15 do f:write(string.format("%02X ",rb(DBG+i))) end
  f:write("\n")
  local pp=rw(PAN)
  if pp~=0 and pp>=0x0100 and pp<0xC000 then
    -- map CODE banks to read string: try current then bank1
    f:write(string.format("panic_str@%04X=",pp))
    for i=0,63 do
      local c=rb(pp+i)
      if c==0 then break end
      if c>=32 and c<127 then f:write(string.char(c)) else f:write(".") end
    end
    f:write("\n")
  end
  f:close()
end
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]; local st=cpu.state
  local iosp=cpu.spaces["io"]
  if iosp then
    iosp:write_u8(0x82, 0x48)
    iosp:write_u8(0xA2, 0x49)
    iosp:write_u8(0xC2, 0x4A)
    iosp:write_u8(0xE2, 0x4B)
  end
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  local dex=rb(DEX)
  if (not armed) and dex>=2 and t>4 then
    armed=true
    dump("armed.txt")
  end
  if not armed then
    if t>=70 then manager.machine:exit() end
    return
  end
  local callno=rb(UD+7)
  if callno~=last_call then
    last_call=callno
    dump(string.format("call_%02X_t%.0f.txt", callno, t))
  end
  if t-last_alive >= 5 then
    last_alive=t
    dump(string.format("alive_t%.0f.txt", t))
  end
  local pan=rw(PAN)
  local halt=st["HALT"].value
  if (not dumped) and (halt~=0 or (pan~=0 and pan>=0x4000 and pan<0xC000)) then
    dumped=true
    dump("panic.txt")
    manager.machine:exit()
  end
  if t>=70 then
    if not dumped then dump("timeout.txt") end
    manager.machine:exit()
  end
end)


-- Stack + IM2 dump when halted after sh ioctl.
local OUTDIR=os.getenv("FUZIX_MAME_OUT") or "."
local DBG,UD=0xFEA1,0xEE00
local DEX,NOEI,FAIL,NULLH=0xFE73,0xFE72,0xFE7B,0xFE76
local R38,R38R,R38SP=0xFE5A,0xFE5D,0xFE5B
local R38UP,R38MP=0xFE62,0xFE65
local KP=0xFE4C
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<55 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]; local iosp=cpu.spaces["io"]; local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  local f=assert(io.open(OUTDIR.."/sh_stack.txt","w"))
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s IFF=%s I=%02X IM=%s\n",
    t,st["PC"].value,st["SP"].value,tostring(st["HALT"].value),
    tostring(st["IFF1"].value), st["I"] and st["I"].value or -1,
    tostring(st["IM"] and st["IM"].value or "?")))
  f:write(string.format("doexec=%02X noei=%02X fail=%02X rst38=%02X ret=%04X rsp=%04X\n",
    rb(DEX),rb(NOEI),rb(FAIL),rb(R38),rw(R38R),rw(R38SP)))
  f:write(string.format("rst38 up %02X %02X %02X mp %02X %02X %02X\n",
    rb(R38UP),rb(R38UP+1),rb(R38UP+2),rb(R38MP),rb(R38MP+1),rb(R38MP+2)))
  f:write(string.format("callno=%02X insys=%02X err=%04X arg=%04X %04X %04X\n",
    rb(UD+7),rb(UD+6),rw(UD+12),rw(UD+18),rw(UD+20),rw(UD+22)))
  f:write(string.format("kp %02X %02X %02X u_page %02X %02X %02X %02X\n",
    rb(KP),rb(KP+1),rb(KP+2),rb(UD+2),rb(UD+3),rb(UD+4),rb(UD+5)))
  f:write(string.format("@EDE4=%04X dbg15=%02X\n", rw(0xEDE4), rb(DBG+15)))
  -- Keep BANK3 mapped (current kp) and dump stack words
  local sp=st["SP"].value
  f:write(string.format("stack@%04X:", sp))
  for i=0,31 do
    f:write(string.format(" %04X", rw((sp+i*2) & 0xFFFF)))
  end
  f:write("\n")
  -- IM2 vectors
  f:write(string.format("FF00=%02X FF01=%02X FFFD=%02X%02X%02X FFFE=%02X FFFF=%02X\n",
    rb(0xFF00),rb(0xFF01),rb(0xFFFD),rb(0xFFFE),rb(0xFFFF),rb(0xFFFE),rb(0xFFFF)))
  f:write(string.format("0038=%02X%02X%02X\n", rb(0x38),rb(0x39),rb(0x3A)))
  -- Map CODE2 and read 6480; map CODE3 and read 6480
  iosp:write_u8(0x82, 0x4C); iosp:write_u8(0xA2, 0x4D)
  f:write(string.format("CODE2@6480=%02X%02X%02X%02X\n", rb(0x6480),rb(0x6481),rb(0x6482),rb(0x6483)))
  iosp:write_u8(0x82, 0x4E); iosp:write_u8(0xA2, 0x4F)
  f:write(string.format("CODE3@6480=%02X%02X%02X%02X\n", rb(0x6480),rb(0x6481),rb(0x6482),rb(0x6483)))
  f:close(); manager.machine:exit()
end)

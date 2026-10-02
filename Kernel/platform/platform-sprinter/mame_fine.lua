-- Sprinter bring-up dump: remap u_page[0] before reading PROGLOAD.
local OUTDIR=os.getenv("FUZIX_MAME_OUT") or "."
local UD=0xEE00
local DEX,NOEI,R38,R38R=0xFED5,0xFED4,0xFEC8,0xFEC9
local KP,MP,RWS=0xFEC4,0xFEC0,0xFEE8
local DBG=0xFED8
local FAIL=0xFED8 -- sprinter_dbg aliases exec_diag; fail_stage is exec_diag+0
local snaps={{8,false},{9,false},{10,false},{12,false},{15,false},{20,false},{30,false}}
local function rb(mem,a) return mem:read_u8(a) end
local function rw(mem,a) return rb(mem,a)+256*rb(mem,a+1) end
local function dump(tag)
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local ios=cpu.spaces["io"]
  local st=cpu.state
  local f=assert(io.open(OUTDIR.."/"..tag,"w"))
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s\n",manager.machine.time:as_double(),st["PC"].value,st["SP"].value,tostring(st["HALT"].value)))
  f:write(string.format("doexec=%02X noei=%02X rst38=%02X ret=%04X\n",rb(mem,DEX),rb(mem,NOEI),rb(mem,R38),rw(mem,R38R)))
  f:write(string.format("callno=%02X insys=%02X err=%04X arg=%04X done=%04X brk=%04X\n",rb(mem,UD+7),rb(mem,UD+6),rw(mem,UD+12),rw(mem,UD+18),rw(mem,UD+0x9F),rw(mem,UD+30)))
  f:write(string.format("kp %02X %02X %02X mp %02X %02X %02X rw=%02X\n",rb(mem,KP),rb(mem,KP+1),rb(mem,KP+2),rb(mem,MP),rb(mem,MP+1),rb(mem,MP+2),rb(mem,RWS)))
  f:write(string.format("dbg %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X\n",
    rb(mem,DBG),rb(mem,DBG+1),rb(mem,DBG+2),rb(mem,DBG+3),
    rb(mem,DBG+4),rb(mem,DBG+5),rb(mem,DBG+6),rb(mem,DBG+7),
    rb(mem,DBG+8),rb(mem,DBG+9),rb(mem,DBG+10),rb(mem,DBG+11)))
  local u0=rb(mem,UD+2)
  local u1=rb(mem,UD+3)
  local u2=rb(mem,UD+4)
  local k0=rb(mem,KP)
  local k1=rb(mem,KP+1)
  local k2=rb(mem,KP+2)
  f:write(string.format("u_page %02X %02X %02X\n",u0,u1,u2))
  -- Only force user WIN0 when not mid-kernel syscall (WIN0 may hold
  -- bounce/CODE0).  After doexec, user map is expected.
  local dex=rb(mem,DEX)
  local insys=rb(mem,UD+6)
  if dex>=2 and insys==0 and u0>=0x08 and u0<0x50 then
    ios:write_u8(0x82, u0)
    if u1>=0x08 and u1<0x50 then ios:write_u8(0xA2, u1) end
  elseif u0>=0x08 and u0<0x50 and insys==1 then
    -- Mid-execve: peek via WIN1 so we do not steal WIN0 from kernel.
    ios:write_u8(0xA2, u0)
    f:write("peekWIN1 "); for i=0,3 do f:write(string.format("%02X ",rb(mem,0x4100+i))) end
    f:write(" @4112 "); for i=0,3 do f:write(string.format("%02X ",rb(mem,0x4112+i))) end
    f:write("\n")
    if k1>=0x08 and k1<0x50 then ios:write_u8(0xA2, k1) end
  end
  f:write("@100 "); for i=0,3 do f:write(string.format("%02X ",rb(mem,0x100+i))) end
  f:write(" @112 "); for i=0,3 do f:write(string.format("%02X ",rb(mem,0x112+i))) end
  f:write(" @0 "); for i=0,3 do f:write(string.format("%02X ",rb(mem,i))) end
  f:write("\n")
  -- Sanitizer-fallback page peek (lost-image hypothesis).
  ios:write_u8(0xA2, 0x08)
  f:write("p08viaWIN1 "); for i=0,3 do f:write(string.format("%02X ",rb(mem,0x4100+i))) end
  f:write("\n")
  if k0>=0x08 and k0<0x50 and dex>=2 and insys==0 then ios:write_u8(0x82, k0) end
  if k1>=0x08 and k1<0x50 then ios:write_u8(0xA2, k1) end
  if k2>=0x08 and k2<0x50 then ios:write_u8(0xC2, k2) end
  f:close()
end
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  for _,s in ipairs(snaps) do
    if (not s[2]) and t>=s[1] then s[2]=true; dump(string.format("s%02d.txt",s[1])) end
  end
  if t>=35 then dump("final.txt"); manager.machine:exit() end
end)

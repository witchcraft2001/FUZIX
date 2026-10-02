-- Dense bring-up dump: catch PROGLOAD wipe between doexec and sbrk.
-- Addresses from fuzix.map (rebuild shifts them!).
local OUTDIR=os.getenv("FUZIX_MAME_OUT") or "."
local UD=0xEE00
local DEX,NOEI,R38,R38R=0xfed5,0xfed4,0xfec8,0xfec9
local KP,MP,DBG=0xfec4,0xfec0,0xfed8
local RELOC=0xf45a
local snaps={}
for t=8.0,12.0,0.25 do snaps[#snaps+1]={t,false} end
for t=12.25,16.0,0.25 do snaps[#snaps+1]={t,false} end
snaps[#snaps+1]={20,false}
snaps[#snaps+1]={30,false}
local function rb(mem,a) return mem:read_u8(a) end
local function rw(mem,a) return rb(mem,a)+256*rb(mem,a+1) end
local function dump(tag)
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local ios=cpu.spaces["io"]
  local st=cpu.state
  local f=assert(io.open(OUTDIR.."/"..tag,"w"))
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s\n",manager.machine.time:as_double(),st["PC"].value,st["SP"].value,tostring(st["HALT"].value)))
  f:write(string.format("doexec=%02X noei=%02X rst38=%02X ret=%04X reloc=%02X\n",rb(mem,DEX),rb(mem,NOEI),rb(mem,R38),rw(mem,R38R),rb(mem,RELOC)))
  f:write(string.format("callno=%02X insys=%02X err=%04X arg=%04X done=%04X brk=%04X\n",rb(mem,UD+7),rb(mem,UD+6),rw(mem,UD+12),rw(mem,UD+18),rw(mem,UD+0x9F),rw(mem,UD+30)))
  f:write(string.format("kp %02X %02X %02X mp %02X %02X %02X\n",rb(mem,KP),rb(mem,KP+1),rb(mem,KP+2),rb(mem,MP),rb(mem,MP+1),rb(mem,MP+2)))
  f:write(string.format("dbg9-14 %02X %02X %02X %02X %02X %02X dbg15=%02X\n",
    rb(mem,DBG+9),rb(mem,DBG+10),rb(mem,DBG+11),rb(mem,DBG+12),rb(mem,DBG+13),rb(mem,DBG+14),rb(mem,DBG+15)))
  local u0,u1,u2=rb(mem,UD+2),rb(mem,UD+3),rb(mem,UD+4)
  local k0,k1,k2=rb(mem,KP),rb(mem,KP+1),rb(mem,KP+2)
  f:write(string.format("u_page %02X %02X %02X\n",u0,u1,u2))
  if u0>=0x08 and u0<0x50 then
    ios:write_u8(0xA2, u0)
    f:write("p0via1 @100 "); for i=0,3 do f:write(string.format("%02X ",rb(mem,0x4100+i))) end
    f:write("@112 "); for i=0,3 do f:write(string.format("%02X ",rb(mem,0x4112+i))) end
    f:write("@0 "); for i=0,3 do f:write(string.format("%02X ",rb(mem,0x4000+i))) end
    f:write("\n")
    -- page1 sample (should stay live if only page0 wiped)
    if u1>=0x08 and u1<0x50 then
      ios:write_u8(0xA2, u1)
      f:write("p1via1 @4100 "); for i=0,3 do f:write(string.format("%02X ",rb(mem,0x4100+i))) end
      f:write(string.format("@6478 %02X\n", rb(mem,0x6478)))
    end
    if k1>=0x08 and k1<0x50 then ios:write_u8(0xA2, k1) end
  end
  if rb(mem,DEX)>=2 and u0>=0x08 and u0<0x50 then
    ios:write_u8(0x82, u0)
    if u1>=0x08 and u1<0x50 then ios:write_u8(0xA2, u1) end
    f:write("live @100 "); for i=0,3 do f:write(string.format("%02X ",rb(mem,0x100+i))) end
    f:write("@112 "); for i=0,3 do f:write(string.format("%02X ",rb(mem,0x112+i))) end
    f:write("@0 "); for i=0,3 do f:write(string.format("%02X ",rb(mem,i))) end
    f:write(string.format("@6478 %02X\n", rb(mem,0x6478)))
    if k0>=0x08 and k0<0x50 then ios:write_u8(0x82, k0) end
    if k1>=0x08 and k1<0x50 then ios:write_u8(0xA2, k1) end
    if k2>=0x08 and k2<0x50 then ios:write_u8(0xC2, k2) end
  end
  f:close()
end
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  for _,s in ipairs(snaps) do
    if (not s[2]) and t>=s[1] then
      s[2]=true
      dump(string.format("t%05d.txt", math.floor(s[1]*100+0.5)))
    end
  end
  if t>=35 then dump("final.txt"); manager.machine:exit() end
end)

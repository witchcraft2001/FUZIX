local OUTDIR=os.getenv("FUZIX_MAME_OUT") or "."
local UD=0xEE00
local DEX,NOEI=0xFEC5,0xFEC4
local PAN,PBY=0xFEA6,0xFEA8
local VDEV,VSITE=0xFEA2,0xFEA4
local DBG,RWS=0xFEEF,0xFEDD
local KP,MP=0xFE9E,0xFE99
local function rb(mem,a) return mem:read_u8(a) end
local function rw(mem,a) return rb(mem,a)+256*rb(mem,a+1) end
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<9.0 then return end
  local cpu=manager.machine.devices[":maincpu"]; local mem=cpu.spaces["program"]; local st=cpu.state
  local pc=st["PC"].value
  if st["HALT"].value~=0 or pc==0xF172 or pc==0xF173 or t>=12 then
    dumped=true
    local f=assert(io.open(OUTDIR.."/panic.txt","w"))
    local pp=rw(mem,PAN)
    f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s\n",t,pc,st["SP"].value,tostring(st["HALT"].value)))
    f:write(string.format("doexec=%02X noei=%02X\n",rb(mem,DEX),rb(mem,NOEI)))
    f:write(string.format("callno=%02X insys=%02X err=%04X done=%04X rw=%02X\n",rb(mem,UD+7),rb(mem,UD+6),rw(mem,UD+12),rw(mem,UD+0x9F),rb(mem,RWS)))
    f:write(string.format("validchk_dev=%04X site=%04X\n",rw(mem,VDEV),rw(mem,VSITE)))
    f:write(string.format("panic_ptr=%04X\n",pp))
    if pp~=0 then
      f:write("panic_str=")
      for i=0,40 do local c=rb(mem,pp+i); if c==0 then break end; if c>=32 and c<127 then f:write(string.char(c)) end end
      f:write("\n")
    end
    f:write(string.format("kp %02X %02X %02X mp %02X %02X %02X\n",rb(mem,KP),rb(mem,KP+1),rb(mem,KP+2),rb(mem,MP),rb(mem,MP+1),rb(mem,MP+2)))
    -- dump udata u_page: search typical offset; also dump EE00+0x80.. 
    f:write("udata_pageish ")
    for off=0x40,0x90 do f:write(string.format("%02X",rb(mem,UD+off))); if (off%16)==15 then f:write(" ") end end
    f:write("\n")
    f:write("dbg "); for i=0,15 do f:write(string.format("%02X ",rb(mem,DBG+i))) end; f:write("\n")
    f:close(); manager.machine:exit()
  end
end)


-- Pure common-memory dump — never remap mpgsel (that stalls the guest).
local OUTDIR="/Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/mame_out"
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<8.0 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  os.execute("mkdir -p "..OUTDIR)
  local f=assert(io.open(OUTDIR.."/hang_noremap.txt","w"))
  f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s IFF1=%s\n",
    t, st["PC"].value, st["SP"].value, tostring(st["HALT"].value),
    tostring(st["IFF1"] and st["IFF1"].value)))
  local pp=rw(0xFE3D)
  f:write(string.format("rw=%02X panic=%04X '", rb(0xFE72), pp))
  if pp ~= 0 then
    for i=0,15 do
      local c=rb(pp+i)
      if c==0 then break end
      if c>=32 and c<127 then f:write(string.char(c)) else f:write(".") end
    end
  end
  f:write(string.format("'\ncallno=%02X insys=%02X err=%04X\n",
    rb(0xEE07), rb(0xEE06), rw(0xEE08)))
  f:write(string.format("rst38=%02X nullh=%02X nmi=%02X\n",
    rb(0xFE43), rb(0xFE5D), rb(0xFE5C)))
  f:write(string.format("u_page %02X %02X %02X %02X mpgsel %02X %02X %02X %02X\n",
    rb(0xEE02),rb(0xEE03),rb(0xEE04),rb(0xEE05),
    rb(0xFE30),rb(0xFE31),rb(0xFE32),rb(0xFE33)))
  f:write(string.format("doexec arm=%02X seen=%02X expect=%04X isp=%04X\n",
    rb(0xFEC1), rb(0xFEC2), rw(0xFEC5), rw(0xFEC7)))
  f:write(string.format("trace_last=%02X dbg=", rb(0xFE5B)))
  for i=0,15 do f:write(string.format("%02X ", rb(0xFEDA+i))) end
  f:write("\n")
  f:write(string.format("pc_bytes=%02X %02X %02X %02X\n",
    rb(st["PC"].value), rb(st["PC"].value+1),
    rb(st["PC"].value+2), rb(st["PC"].value+3)))
  f:write("FE62..71=")
  for a=0xFE62,0xFE71 do f:write(string.format("%02X ", rb(a))) end
  f:write("\n")
  f:close()
  manager.machine:exit()
end)

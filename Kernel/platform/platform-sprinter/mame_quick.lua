local OUTDIR = os.getenv("FUZIX_MAME_OUT")
local DUMP_AT = tonumber(os.getenv("FUZIX_MAME_DUMP_AT") or "5")
local EXIT_AT = tonumber(os.getenv("FUZIX_MAME_EXIT_AT") or "6")
local dumped=false
local function hex(mem,base,len)
  local t={}
  for i=0,len-1 do t[#t+1]=string.format("%02X", mem:read_u8(base+i)) end
  return table.concat(t," ")
end
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if (not dumped) and t>=DUMP_AT then
    dumped=true
    local cpu=manager.machine.devices[":maincpu"]
    local st=cpu.state
    local mem=cpu.spaces["program"]
    local f=assert(io.open(OUTDIR.."/quick.txt","w"))
    f:write(string.format("PC=%04X SP=%04X PG0=%s PG1=%s PG2=%s PG3=%s\n",
      st["PC"].value, st["SP"].value,
      tostring(st["PG0"].value), tostring(st["PG1"].value),
      tostring(st["PG2"].value), tostring(st["PG3"].value)))
    f:write("FE40: "..hex(mem,0xFE40,0x80).."\n")
    f:write("FD70: "..hex(mem,0xFD70,0x80).."\n")
    f:write("EE00: "..hex(mem,0xEE00,0x20).."\n")
    f:write("0100: "..hex(mem,0x0100,0x20).."\n")
    f:write("0000: "..hex(mem,0x0000,0x10).."\n")
    -- kernel_pages / mpgsel at known symbols
    f:write(string.format("fail_stage@FDBC? check map\n"))
    -- find by scanning for E3 marker in FE40-FE80
    for a=0xFE40,0xFE7F do
      if mem:read_u8(a)==0xE3 then
        f:write(string.format("E3 at %04X context: %s\n", a, hex(mem,a-8,24)))
      end
    end
    f:close()
  end
  if t>=EXIT_AT then manager.machine:exit() end
end)

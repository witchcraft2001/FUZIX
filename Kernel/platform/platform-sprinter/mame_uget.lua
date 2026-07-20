local OUTDIR = os.getenv("FUZIX_MAME_OUT") or "."
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<5.5 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local iosp=cpu.spaces["io"]
  local f=assert(io.open(OUTDIR.."/uget.txt","w"))
  local function rb(a) return mem:read_u8(a) end
  -- ensure common page
  iosp:write_u8(0xE2, 0x4B)
  f:write("live FCB0:")
  for i=0,80 do f:write(string.format(" %02X", rb(0xFCB0+i))) end
  f:write("\nlive FDE0:")
  for i=0,80 do f:write(string.format(" %02X", rb(0xFDE0+i))) end
  f:write("\nlive C3B0:")
  for i=0,32 do f:write(string.format(" %02X", rb(0xC3B0+i))) end
  f:write(string.format("\nMPGSEL ports read if possible; cache=%02X %02X %02X %02X\n",
    rb(0xFE13), rb(0xFE14), rb(0xFE15), rb(0xFE16)))
  f:write(string.format("rst ret=%04X count=%02X\n", rb(0xFE29)+256*rb(0xFE2A), rb(0xFE26)))
  -- HL DE BC from dbg
  f:write(string.format("dbg BC=%02X%02X DE=%02X%02X HL=%02X%02X\n",
    rb(0xFEDF+5), rb(0xFEDF+4), rb(0xFEDF+7), rb(0xFEDF+6),
    rb(0xFEDF+9), rb(0xFEDF+8)))
  f:close()
end)

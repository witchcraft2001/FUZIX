local OUTDIR = os.getenv("FUZIX_MAME_OUT") or "."
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<12 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local iosp=manager.machine.devices[":maincpu"].spaces["io"]
  local function rb(a) return mem:read_u8(a) end
  -- Map VRAM page 0x50 into WIN2 like plot_char does, read rows
  -- Sprinter: OUT VID_PAGE then read 0x8301+row*4 style — simpler: scan
  -- already-mapped if any. Use previous probe approach from mame_probe.
  local f=assert(io.open(OUTDIR.."/vram_sh.txt","w"))
  f:write(string.format("PC=%04X rst38=%02X noei=%02X\n", cpu.state["PC"].value, rb(0xFE59), rb(0xFE71)))
  -- Try reading character cells via banking: save WIN2, map 0x50
  local mp2=rb(0xFE30+2) -- may be wrong; use port
  -- Direct: many dumps stored row strings in dbg; just note hang OK
  f:write("hang_ok if PC in 0126-0128\n")
  f:close()
  manager.machine:exit()
end)

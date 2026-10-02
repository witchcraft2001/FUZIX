-- Dump kernel stack at RST38 entry (sp_latch) for call-chain decode.
local OUTDIR="/Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/mame_out"
local RST38=0xFEA9
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<12.0 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local iosp=cpu.spaces["io"]
  local st=cpu.state
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  os.execute("mkdir -p "..OUTDIR)
  local f=assert(io.open(OUTDIR.."/rst38_stack.txt","w"))
  -- Force CODE3 map as at trap
  iosp:write_u8(0x82,0x48); iosp:write_u8(0xA2,0x4E); iosp:write_u8(0xC2,0x4F)
  local spl=rw(RST38+1)
  local ret=rw(RST38+3)
  f:write(string.format("spl=%04X ret=%04X count=%02X\n", spl, ret, rb(RST38)))
  f:write("stack_words=")
  for i=0,31 do f:write(string.format("%04X ", rw(spl+i*2))) end
  f:write("\n")
  -- annotate likely code addresses
  f:write("near_symbols_guess: look up words in 0x0100-0xB000 against map\n")
  for i=0,31 do
    local w=rw(spl+i*2)
    if w >= 0x100 and w < 0xC000 then
      f:write(string.format("  [%d] %04X bytes=", i, w))
      for j=-2,6 do f:write(string.format("%02X ", rb(w+j))) end
      f:write("\n")
    end
  end
  f:close()
  manager.machine:exit()
end)

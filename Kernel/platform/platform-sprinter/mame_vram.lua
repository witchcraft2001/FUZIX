local OUTDIR = os.getenv("FUZIX_MAME_OUT") or "."
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<14 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local iosp=cpu.spaces["io"]
  local f=assert(io.open(OUTDIR.."/vram.txt","w"))
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  f:write(string.format("PC=%04X HALT=%s rst=%02X ret=%04X err=%04X rw=%02X\n",
    cpu.state["PC"].value, tostring(cpu.state["HALT"].value),
    rb(0xFE26), rw(0xFE29), rw(0xEE0C), rb(0xFE77)))
  f:write(string.format("dbg:"))
  for i=0,31 do f:write(string.format(" %02X", rb(0xFEDF+i))) end
  f:write("\n")
  -- Map VRAM page 0x50 into WIN2 and scrape 80x25 text Mode1 cells
  iosp:write_u8(0xC2, 0x50)
  for row=0,24 do
    local line={}
    for col=0,79 do
      iosp:write_u8(0x89, (col+1)|0x80)  -- VID_PAGE PORT_Y?
      local hl = 0x8301 + row*4
      -- Actually from init_hardware: out VID_PAGE=(col+1)|0x80, HL=0x8301+row*4
      -- Need correct ports from kernel.def
      line[#line+1] = string.char(rb(hl) > 0 and rb(hl) or 32)
    end
    -- This per-col page switch approach is slow/wrong without proper PORT_Y
  end
  -- Simpler: use dbg/boot marks already on screen via previous method
  -- Read rows using sprvideo layout: for each row, set page once per col
  local rows={}
  for row=0,31 do
    local chars={}
    for col=0,79 do
      local py = ((col+1) | 0x80) & 0xFF
      iosp:write_u8(0x89, py)
      local addr = 0x8301 + row*4
      local ch = rb(addr)
      if ch < 32 or ch > 126 then ch = 46 end
      chars[#chars+1]=string.char(ch)
    end
    rows[#rows+1]=table.concat(chars)
  end
  for i,r in ipairs(rows) do
    local t=r:gsub("%s+$","")
    if t:match("%S") then f:write(string.format("R%02d|%s\n", i-1, t)) end
  end
  f:close()
  manager.machine:exit()
end)

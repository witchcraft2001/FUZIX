-- Stable idle dump. sprinit_raw: stage@01A1 wr@01A2 wr2@01A4 spin@01A6
local OUTDIR = os.getenv("FUZIX_MAME_OUT") or "."
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if dumped or t<10.0 then return end
  dumped=true
  local cpu=manager.machine.devices[":maincpu"]
  local mem=cpu.spaces["program"]
  local iosp=cpu.spaces["io"]
  local st=cpu.state
  local f=assert(io.open(OUTDIR.."/pause.txt","w"))
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a)+256*rb(a+1) end
  f:write(string.format("PC=%04X SP=%04X HALT=%s\n", st["PC"].value, st["SP"].value, tostring(st["HALT"].value)))
  f:write(string.format("err=%04X rst38=%02X FF00=%02X FFFD=%02X%02X%02X\n",
    rw(0xEE0C), rb(0xFE43), rb(0xFF00), rb(0xFFFD), rb(0xFFFE), rb(0xFFFF)))
  iosp:write_u8(0x82, 0x44); iosp:write_u8(0xA2, 0x45); iosp:write_u8(0xC2, 0x46)
  f:write(string.format("USER stage=%02X wr=%04X wr2=%04X spin=%02X\n",
    rb(0x01A1), rw(0x01A2), rw(0x01A4), rb(0x01A6)))
  iosp:write_u8(0xC2, 0x50)
  for row=14,17 do
    local chars={}
    for col=0,39 do
      iosp:write_u8(0x89, ((col+1)|0x80)&0xFF)
      local ch=rb(0x8301+row*4)
      if ch<32 or ch>126 then ch=46 end
      chars[#chars+1]=string.char(ch)
    end
    f:write(string.format("R%02d|%s\n", row, table.concat(chars):gsub("%s+$","")))
  end
  f:close()
end)

local OUTDIR = os.getenv("FUZIX_MAME_OUT") or "."
local DUMP_AT = tonumber(os.getenv("FUZIX_MAME_DUMP_AT") or "6")
local EXIT_AT = tonumber(os.getenv("FUZIX_MAME_EXIT_AT") or "7")
local dumped=false
local function dump(f,mem,a,n,lab)
  f:write(string.format("%s@%04X:", lab,a))
  for i=0,n-1 do
    if i%16==0 then f:write(string.format("\n%04X:", a+i)) end
    f:write(string.format(" %02X", mem:read_u8(a+i)))
  end
  f:write("\n")
end
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if (not dumped) and t>=DUMP_AT then
    dumped=true
    local mem=manager.machine.devices[":maincpu"].spaces["program"]
    local f=assert(io.open(OUTDIR.."/ino.txt","w"))
    -- buf1 @2A11 is blk 0x12; inode 131 at index 3 → +192
    dump(f,mem,0x2A11,64,"ino128")
    dump(f,mem,0x2A11+64,64,"ino129")
    dump(f,mem,0x2A11+128,64,"ino130")
    dump(f,mem,0x2A11+192,64,"ino131")
    -- compare with disk
    f:write(string.format("busy buf1=%02X buf2=%02X\n", mem:read_u8(0x2A11+517), mem:read_u8(0x2C19+517)))
    -- screen row via known pattern
    f:write(string.format("fail=%02X err=%04X\n", mem:read_u8(0xFDB6), mem:read_u16(0xFDB7)))
    -- scan for "bad disk" or "iobad"
    local needle="iobad"
    for a=0xC300,0xEE00-5 do
      local ok=true
      for i=1,#needle do
        if mem:read_u8(a+i-1)~=string.byte(needle,i) then ok=false break end
      end
      if ok then f:write(string.format("found iobad string ref use at runtime screen instead\n")) break end
    end
    f:close()
  end
  if t>=EXIT_AT then manager.machine:exit() end
end)

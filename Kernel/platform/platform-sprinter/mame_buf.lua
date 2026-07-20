local OUTDIR = os.getenv("FUZIX_MAME_OUT") or "."
local DUMP_AT = tonumber(os.getenv("FUZIX_MAME_DUMP_AT") or "6")
local EXIT_AT = tonumber(os.getenv("FUZIX_MAME_EXIT_AT") or "7")
local dumped=false
emu.register_frame(function()
  local t=manager.machine.time:as_double()
  if (not dumped) and t>=DUMP_AT then
    dumped=true
    local mem=manager.machine.devices[":maincpu"].spaces["program"]
    local f=assert(io.open(OUTDIR.."/buf.txt","w"))
    local bend=mem:read_u16(0x0FC4)
    f:write(string.format("bufpool_end_ptr_var@0FC4 value=%04X\n", bend))
    f:write(string.format("bufpool@2809 first_non_zero scan:\n"))
    local first=-1
    for a=0x2809,0x2809+5*520-1 do
      if mem:read_u8(a)~=0 then first=a break end
    end
    f:write(string.format("first_nonzero=%s\n", first>=0 and string.format("%04X",first) or "NONE"))
    -- scan WIN0+common for dirent init (83 00 69 6E 69 74)
    local hits={}
    for a=0x0000,0xFFFF-6 do
      if mem:read_u8(a)==0x83 and mem:read_u8(a+1)==0x00 and mem:read_u8(a+2)==0x69 and mem:read_u8(a+3)==0x6E and mem:read_u8(a+4)==0x69 and mem:read_u8(a+5)==0x74 then
        hits[#hits+1]=a
        if #hits>=12 then break end
      end
    end
    f:write("init dirent hits:")
    for _,a in ipairs(hits) do f:write(string.format(" %04X",a)) end
    f:write("\n")
    -- dump each hit context
    for _,a in ipairs(hits) do
      f:write(string.format(" @%04X:", a-2))
      for i=-2,33 do f:write(string.format(" %02X", mem:read_u8(a+i))) end
      f:write("\n")
    end
    -- dump blkbuf headers if bend looks sane
    if bend>0x2809 and bend<0xC000 then
      local n=math.floor((bend-0x2809)/520)
      f:write(string.format("approx_bufs=%d\n", n))
      for i=0,math.min(n-1,7) do
        local b=0x2809+i*520
        f:write(string.format("buf%d@%04X data[0..15]=", i, b))
        for j=0,15 do f:write(string.format("%02X ", mem:read_u8(b+j))) end
        f:write(string.format(" dev=%04X blk=%04X dirty=%02X busy=%02X\n",
          mem:read_u16(b+512), mem:read_u16(b+514), mem:read_u8(b+516), mem:read_u8(b+517)))
      end
    end
    -- also check if bufpool uses external and size differs - sizeof
    -- try 512+8=520 and also scan for bf_dev==1 bf_blk==256
    f:write("scan bf_dev=0001 bf_blk=0100 near 2809-4000:\n")
    for a=0x2809,0x4000-6 do
      if mem:read_u16(a)==1 and mem:read_u16(a+2)==0x100 then
        f:write(string.format(" hit meta@%04X\n", a))
      end
    end
    f:write("scan C300-EE00 same:\n")
    for a=0xC300,0xEE00-6 do
      if mem:read_u16(a)==1 and mem:read_u16(a+2)==0x100 then
        f:write(string.format(" hit meta@%04X\n", a))
      end
    end
    f:close()
  end
  if t>=EXIT_AT then manager.machine:exit() end
end)

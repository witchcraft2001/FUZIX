local dumped = false
print("OFT SCRIPT LOADED")
emu.register_frame(function()
  if dumped then return end
  local t = emu.time()
  if t < 5.5 then return end
  dumped = true
  print("OFT SCRIPT DUMP t=" .. t)
  local cpu = manager.machine.devices[":maincpu"]
  local prog = cpu.spaces["program"]
  local f = assert(io.open("/tmp/oft.txt", "w"))
  local function rb(a) return prog:read_u8(a) end
  local function rw(a) return rb(a) + 256 * rb(a + 1) end
  -- try remap
  local io = cpu.spaces["io"]
  if io then
    io:write_u8(0x82, 0x48)
    io:write_u8(0xA2, 0x49)
    io:write_u8(0xC2, 0x4A)
    f:write("remapped via io\n")
  else
    f:write("no io space\n")
  end
  f:write(string.format("files=%02X %02X %02X err=%04X\n",
    rb(0xEE80), rb(0xEE81), rb(0xEE82), rw(0xEE0C)))
  local oft = 0x14CF
  for e = 0, 3 do
    local b = oft + e * 8
    f:write(string.format("oft[%d]:", e))
    for i = 0, 7 do f:write(string.format(" %02X", rb(b + i))) end
    f:write(string.format(" ino=%04X\n", rw(b)))
  end
  local ino = rw(oft + 8)
  f:write(string.format("ino1=%04X\n", ino))
  if ino ~= 0 and ino < 0xC000 then
    f:write("inode:")
    for i = 0, 79 do f:write(string.format(" %02X", rb(ino + i))) end
    f:write("\n")
    -- c_magic at 0, c_dev at 2, c_num at 4, c_node.i_mode at 6
    f:write(string.format("magic=%04X dev=%04X num=%04X mode=%04X addr0=%04X\n",
      rw(ino), rw(ino+2), rw(ino+4), rw(ino+6), rw(ino+6+24)))
  end
  f:close()
  print("OFT SCRIPT DONE")
  manager.machine:exit()
end)

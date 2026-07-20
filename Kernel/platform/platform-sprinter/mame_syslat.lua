local OUTDIR = os.getenv("FUZIX_MAME_OUT") or "/tmp/fuzix_mame"
local dumped = false
emu.register_frame(function()
  if dumped then return end
  if emu.time() < 5.5 then return end
  dumped = true
  local cpu = manager.machine.devices[":maincpu"]
  local mem = cpu.spaces["program"]
  local f = assert(io.open(OUTDIR .. "/syslat.txt", "w"))
  local function rb(a) return mem:read_u8(a) end
  local function rw(a) return rb(a) + 256 * rb(a + 1) end
  f:write(string.format("PC=%04X SP=%04X HALT=%s\n", cpu.state["PC"].value, cpu.state["SP"].value, tostring(cpu.state["HALT"].value)))
  f:write(string.format("PG=%02X/%02X/%02X/%02X\n",
    cpu.state["PG0"] and cpu.state["PG0"].value or 0,
    cpu.state["PG1"] and cpu.state["PG1"].value or 0,
    cpu.state["PG2"] and cpu.state["PG2"].value or 0,
    cpu.state["PG3"] and cpu.state["PG3"].value or 0))
  f:write(string.format("initio stage=%02X fd=%04X err=%04X files=%02X %02X %02X\n",
    rb(0xFE36), rw(0xFE39), rw(0xFE3B), rb(0xFE38), rb(0xFE38+1), rb(0xFE38+2)))
  -- u_files: find by scanning udata for pattern; offsetof approx from struct
  -- From kernel.h after known fields: use map/gdb-less probe of EE00+0xB0 area
  f:write("udata head: ")
  for i=0,31 do f:write(string.format("%02X ", rb(0xEE00+i))) end
  f:write("\n")
  -- dump likely u_files region: after sigvec etc. Try offsets 0xB0..0xD0
  for off=0xA0,0xE0,16 do
    f:write(string.format("EE%02X:", off))
    for i=0,15 do f:write(string.format(" %02X", rb(0xEE00+off+i))) end
    f:write("\n")
  end
  f:write(string.format("enter no=%02X fix=%02X exit no=%02X err=%04X\n",
    rb(0xFE6D), rb(0xFE76), rb(0xFE77), rw(0xFE78)))
  f:write(string.format("u_error=%04X callno=%02X insys=%02X arg=%04X %04X %04X\n",
    rw(0xEE0C), rb(0xEE07), rb(0xEE06), rw(0xEE12), rw(0xEE14), rw(0xEE16)))
  -- of_tab[0] at 0x14CF - may need kernel map; try anyway with current PG
  f:write(string.format("of0 refs/inode peek @14CF:"))
  for i=0,15 do f:write(string.format(" %02X", rb(0x14CF+i))) end
  f:write("\n")
  f:write(string.format("dev_tab@0F7F:"))
  for i=0,39 do f:write(string.format(" %02X", rb(0x0F7F+i))) end
  f:write("\n")
  f:close()
  manager.machine:exit()
end)

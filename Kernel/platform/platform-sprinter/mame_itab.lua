-- Dump i_tab / of_tab for inode bounds investigation
local OUTDIR = os.getenv("FUZIX_MAME_OUT") or "."
local dumped = false

emu.register_frame(function()
	local t = manager.machine.time:as_double()
	if dumped or t < 5.5 then return end
	dumped = true
	local cpu = manager.machine.devices[":maincpu"]
	local mem = cpu.spaces["program"]
	local iosp = cpu.spaces["io"]
	iosp:write_u8(0x82, 0x48)
	iosp:write_u8(0xA2, 0x49)
	iosp:write_u8(0xC2, 0x4A)
	local f = assert(io.open(OUTDIR .. "/itab.txt", "w"))
	local function rb(a) return mem:read_u8(a) end
	local function rw(a) return rb(a) + 256 * rb(a + 1) end
	f:write("of_tab raw:\n")
	for i = 0, 63 do
		if (i % 16) == 0 then f:write(string.format("%04X:", 0x14CF + i)) end
		f:write(string.format(" %02X", rb(0x14CF + i)))
		if (i % 16) == 15 then f:write("\n") end
	end
	f:write("\ni_tab populated slots (sz=75):\n")
	local base = 0x164F
	local sz = 75
	for n = 0, 39 do
		local a = base + n * sz
		local mag = rw(a)
		if mag == 0x6091 then
			f:write(string.format(" [%2d] @%04X mode=%04X addr0=%04X refs=%02X num=%04X\n",
				n, a, rw(a + 6), rw(a + 6 + 24), rb(a + 6 + 64), rw(a + 4)))
		end
	end
	f:write(string.format("\ni_tab end=%04X\n", base + 40 * sz))
	f:write(string.format("at 2250: mag=%04X mode=%04X addr0=%04X\n",
		rw(0x2250), rw(0x2256), rw(0x2250 + 6 + 24)))
	f:write("CMAGIC scan 1600-2300:\n")
	for a = 0x1600, 0x2300, 1 do
		if rw(a) == 0x6091 then
			f:write(string.format(" %04X (off=%d)\n", a, a - base))
		end
	end
	f:close()
	manager.machine:exit()
end)

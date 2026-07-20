local OUTDIR = os.getenv("FUZIX_MAME_OUT") or "."
local DUMP_AT = tonumber(os.getenv("FUZIX_MAME_DUMP_AT") or "5.5")
local EXIT_AT = tonumber(os.getenv("FUZIX_MAME_EXIT_AT") or "7")
local dumped = false
-- Refresh these from Kernel/fuzix.map after every rebuild.
local STAGE = 0xFDE8
local ERR = 0xFDE9
local INO = 0xFDF1
local MODE = 0xFDF3
local PERM = 0xFDF5
local NAME = 0xFDEB
local PATH = 0xF431
local ITAB = 0x16DD
local NNAME = 0xF43D
local NSTAGE = 0xFE1A
local IOPEN_RET = 0xFE1E
local PANIC_PTR = 0xFDC3
local PANIC_BYTES = 0xFDC5
emu.register_frame(function()
	local t = manager.machine.time:as_double()
	if (not dumped) and t >= DUMP_AT then
		dumped = true
		local cpu = manager.machine.devices[":maincpu"]
		local mem = cpu.spaces["program"]
		local st = cpu.state
		local iosp = cpu.spaces["io"]
		local f = assert(io.open(OUTDIR .. "/exec.txt", "w"))
		local function rb(a) return mem:read_u8(a) end
		local function rw(a) return rb(a) + 256 * rb(a + 1) end
		-- Live banks first (before any forced remap).
		f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s livePG=%s/%s/%s/%s\n",
			t, st["PC"].value, st["SP"].value, tostring(st["HALT"].value),
			tostring(st["PG0"].value), tostring(st["PG1"].value),
			tostring(st["PG2"].value), tostring(st["PG3"].value)))
		-- Remap kernel for common/DATA dumps.
		if iosp then
			iosp:write_u8(0x82, 0x48)
			iosp:write_u8(0xA2, 0x49)
			iosp:write_u8(0xC2, 0x4A)
			iosp:write_u8(0xE2, 0x4B)
		end
		f:write(string.format("stage=%02X err=%04X ino=%04X mode=%04X perm=%02X name=%04X\n",
			rb(STAGE), rw(ERR), rw(INO), rw(MODE), rb(PERM), rw(NAME)))
		f:write(string.format("nopen_stage=%02X nopen_name=%04X iopen_ret=%04X\n",
			rb(NSTAGE), rw(NNAME), rw(IOPEN_RET)))
		f:write(string.format("panic_ptr=%04X bytes:", rw(PANIC_PTR)))
		for i=0,3 do f:write(string.format(" %02X", rb(PANIC_BYTES+i))) end
		f:write(string.format("\npath:"))
		for i=0,7 do f:write(string.format(" %02X", rb(PATH+i))) end
		f:write(string.format("\nitab0 magic=%04X mode=%04X\n", rw(ITAB), rw(ITAB+6)))
		if rw(INO) >= ITAB and rw(INO) < ITAB + 0xBB8 then
			local p=rw(INO)
			f:write(string.format("ino@%04X magic=%04X mode=%04X refs=%02X\n", p, rw(p), rw(p+6), rb(p+70)))
		end
		f:close()
	end
	if t >= EXIT_AT then manager.machine:exit() end
end)

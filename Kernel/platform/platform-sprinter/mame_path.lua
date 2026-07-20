local OUTDIR = os.getenv("FUZIX_MAME_OUT") or "."
local DUMP_AT = tonumber(os.getenv("FUZIX_MAME_DUMP_AT") or "5.0")
local EXIT_AT = tonumber(os.getenv("FUZIX_MAME_EXIT_AT") or "7")
local dumped = false
-- from fuzix.map
local PATH = 0xF431
local ARGV = 0xF437
local UDATA = 0xEE00
emu.register_frame(function()
	local t = manager.machine.time:as_double()
	if (not dumped) and t >= DUMP_AT then
		dumped = true
		local cpu = manager.machine.devices[":maincpu"]
		local mem = cpu.spaces["program"]
		local st = cpu.state
		local f = assert(io.open(OUTDIR .. "/path.txt", "w"))
		local function rb(a) return mem:read_u8(a) end
		local function rw(a) return rb(a) + 256 * rb(a + 1) end
		f:write(string.format("t=%.2f PC=%04X SP=%04X PG=%s/%s/%s/%s\n",
			t, st["PC"].value, st["SP"].value,
			tostring(st["PG0"].value), tostring(st["PG1"].value),
			tostring(st["PG2"].value), tostring(st["PG3"].value)))
		f:write("path@F431:")
		for i = 0, 15 do f:write(string.format(" %02X", rb(PATH + i))) end
		f:write("\n")
		f:write(string.format("argv0=%04X argv1=%04X envp0=%04X\n",
			rw(ARGV), rw(ARGV + 2), rw(ARGV + 4)))
		f:write(string.format("u_sysio=%02X u_argn=%04X u_argn1=%04X u_argn2=%04X\n",
			rb(UDATA + 0x6C), rw(UDATA + 0x12), rw(UDATA + 0x14), rw(UDATA + 0x16)))
		-- also dump where static name might be - find _name in map if exported
		f:close()
	end
	if t >= EXIT_AT then manager.machine:exit() end
end)

-- Focused dump for /init open failure (ENOENT + RST38@C000)
local OUTDIR = os.getenv("FUZIX_MAME_OUT") or "."
local DUMP_AT = tonumber(os.getenv("FUZIX_MAME_DUMP_AT") or "6")
local EXIT_AT = tonumber(os.getenv("FUZIX_MAME_EXIT_AT") or "7")
local dumped = false

local function dump_mem(f, mem, addr, len, label)
	f:write(string.format("%s@%04X:", label, addr))
	for i = 0, len - 1 do
		if i % 16 == 0 then
			f:write(string.format("\n%04X:", addr + i))
		end
		f:write(string.format(" %02X", mem:read_u8(addr + i)))
	end
	f:write("\n")
end

emu.register_frame(function()
	local t = manager.machine.time:as_double()
	if (not dumped) and t >= DUMP_AT then
		dumped = true
		local cpu = manager.machine.devices[":maincpu"]
		local st = cpu.state
		local mem = cpu.spaces["program"]
		local f = assert(io.open(OUTDIR .. "/open.txt", "w"))
		f:write(string.format("t=%.3f PC=%04X SP=%04X\n", t, st["PC"].value, st["SP"].value))
		f:write(string.format("PG=%s/%s/%s/%s\n",
			tostring(st["PG0"].value), tostring(st["PG1"].value),
			tostring(st["PG2"].value), tostring(st["PG3"].value)))
		f:write(string.format("fail_stage=%02X err=%04X name=%04X root=%04X cwd=%04X ino=%04X\n",
			mem:read_u8(0xFDB6), mem:read_u16(0xFDB7), mem:read_u16(0xFDB9),
			mem:read_u16(0xFDBB), mem:read_u16(0xFDBD), mem:read_u16(0xFDBF)))
		f:write(string.format("nopen stage=%02X name0=%02X char=%02X wd=%04X ninode=%04X\n",
			mem:read_u8(0xFDE8), mem:read_u8(0xFDE9), mem:read_u8(0xFDEA),
			mem:read_u16(0xFDEB), mem:read_u16(0xFDED)))
		f:write(string.format("rst38 count=%02X sp=%04X ret=%04X\n",
			mem:read_u8(0xFD97), mem:read_u16(0xFD98), mem:read_u16(0xFD9A)))
		f:write(string.format("root_dev@105B=%04X root_ptr@105F=%04X\n",
			mem:read_u16(0x105B), mem:read_u16(0x105F)))
		f:write(string.format("udata u_error=%04X u_sysio=%02X u_root=%04X u_cwd=%04X argn=%04X\n",
			mem:read_u16(0xEE0C), mem:read_u8(0xEE07),
			mem:read_u16(0xEE6A), mem:read_u16(0xEE6C), mem:read_u16(0xEE12)))
		-- udata layout may differ; also dump EE00-EE7F raw
		dump_mem(f, mem, 0xEE00, 0x80, "udata")
		dump_mem(f, mem, 0x1050, 0x20, "root_globals")
		dump_mem(f, mem, 0x16A3, 0x80, "i_tab0")
		dump_mem(f, mem, 0x2210, 0x50, "cinode2210")
		dump_mem(f, mem, 0x25EB, 0x20, "lastname")
		dump_mem(f, mem, 0x2809, 0x40, "bufpool_hdr")
		dump_mem(f, mem, 0xC000, 0x20, "c000")
		dump_mem(f, mem, 0xEFC0, 0x40, "stack")
		dump_mem(f, mem, 0xFD70, 0xA0, "diag")
		dump_mem(f, mem, 0xFE50, 0x20, "dbg")
		-- screen grid row 7
		f:write("screen_hint: see probe grid\n")
		f:close()
	end
	if t >= EXIT_AT then manager.machine:exit() end
end)

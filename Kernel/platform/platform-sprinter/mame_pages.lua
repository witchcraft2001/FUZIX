-- Dump physical RAM pages via MAME memory regions if available.
local OUTDIR = os.getenv("FUZIX_MAME_OUT")
local DUMP_AT = tonumber(os.getenv("FUZIX_MAME_DUMP_AT") or "6")
local EXIT_AT = tonumber(os.getenv("FUZIX_MAME_EXIT_AT") or "7")
local dumped = false

local function hex(reg, off, len)
	local t = {}
	for i = 0, len - 1 do
		local ok, b = pcall(function() return reg:read_u8(off + i) end)
		if not ok then b = 0 end
		t[#t + 1] = string.format("%02X", b)
	end
	return table.concat(t, " ")
end

emu.register_frame(function()
	local t = manager.machine.time:as_double()
	if (not dumped) and t >= DUMP_AT then
		dumped = true
		local machine = manager.machine
		local cpu = machine.devices[":maincpu"]
		local st = cpu.state
		local mem = cpu.spaces["program"]
		local f = assert(io.open(OUTDIR .. "/pages.txt", "w"))
		f:write(string.format("PC=%04X SP=%04X\n", st["PC"].value, st["SP"].value))
		f:write(string.format("PG=%s/%s/%s/%s\n",
			tostring(st["PG0"].value), tostring(st["PG1"].value),
			tostring(st["PG2"].value), tostring(st["PG3"].value)))

		-- program space windows
		f:write("prog0000: ")
		for i = 0, 15 do f:write(string.format("%02X ", mem:read_u8(i))) end
		f:write("\nprog0100: ")
		for i = 0, 31 do f:write(string.format("%02X ", mem:read_u8(0x100 + i))) end
		f:write("\n")

		-- doexec / dbg
		f:write(string.format("arm=%02X seen=%02X expect=%04X isp=%04X call=%02X\n",
			mem:read_u8(0xFE37), mem:read_u8(0xFE38),
			mem:read_u16(0xFE3B), mem:read_u16(0xFE3D),
			mem:read_u8(0xFE46)))
		f:write(string.format("fail_stage=%02X nullh=%02X rst38=%02X\n",
			mem:read_u8(0xFDB6), mem:read_u8(0xFDB1), mem:read_u8(0xFD97)))
		f:write(string.format("u_page=%02X%02X%02X%02X insys=%02X\n",
			mem:read_u8(0xEE02), mem:read_u8(0xEE03),
			mem:read_u8(0xEE04), mem:read_u8(0xEE05),
			mem:read_u8(0xEE06)))
		f:write("dbg: ")
		for i = 0, 31 do f:write(string.format("%02X ", mem:read_u8(0xFE50 + i))) end
		f:write("\n")

		f:write("-- regions --\n")
		local ok, regs = pcall(function() return machine.memory.regions end)
		if ok and regs then
			for tag, reg in pairs(regs) do
				local size = reg.bytes or reg.size or 0
				f:write(string.format("%s size=%d\n", tostring(tag), size))
				-- Sprinter RAM is often :maincpu or :ram
				if size >= 0x100000 or tostring(tag):find("ram") or tostring(tag):find("main") then
					-- page 0x44 at 16K stride if linear
					local page = 0x44
					local base = page * 0x4000
					if base + 0x120 < size then
						f:write(string.format("page44@%X+100: %s\n", base, hex(reg, base + 0x100, 32)))
						f:write(string.format("page44@%X+000: %s\n", base, hex(reg, base, 16)))
					end
					local base48 = 0x48 * 0x4000
					if base48 + 0x120 < size then
						f:write(string.format("page48@%X+100: %s\n", base48, hex(reg, base48 + 0x100, 32)))
						f:write(string.format("page48@%X+000: %s\n", base48, hex(reg, base48, 16)))
					end
				end
			end
		end
		f:close()
	end
	if t >= EXIT_AT then manager.machine:exit() end
end)

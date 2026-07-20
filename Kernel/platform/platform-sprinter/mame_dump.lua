-- Sprinter FUZIX bring-up dump helper for MAME.
-- Usage:
--   FUZIX_MAME_OUT=... FUZIX_MAME_DUMP_AT=10 FUZIX_MAME_EXIT_AT=11 \
--   ./mame sprinter ... -autoboot_script mame_dump.lua -seconds_to_run 12 -nodebug

local OUTDIR = os.getenv("FUZIX_MAME_OUT") or "/tmp/fuzix_mame"
local DUMP_AT = tonumber(os.getenv("FUZIX_MAME_DUMP_AT") or "10")
local EXIT_AT = tonumber(os.getenv("FUZIX_MAME_EXIT_AT") or "11")

local dumped = false

local function ensure_outdir()
	os.execute("mkdir -p '" .. OUTDIR .. "'")
end

local function hexdump(mem, base, len)
	local lines = {}
	local i = 0
	while i < len do
		local parts = { string.format("%04X:", base + i) }
		local j = 0
		while j < 16 and (i + j) < len do
			parts[#parts + 1] = string.format(" %02X", mem:read_u8(base + i + j))
			j = j + 1
		end
		lines[#lines + 1] = table.concat(parts)
		i = i + 16
	end
	return table.concat(lines, "\n")
end

local function read_cstr(mem, addr, maxlen)
	local t = {}
	for i = 0, (maxlen or 64) - 1 do
		local b = mem:read_u8(addr + i)
		if b == 0 then
			break
		end
		if b >= 32 and b < 127 then
			t[#t + 1] = string.char(b)
		else
			t[#t + 1] = string.format("\\x%02X", b)
		end
	end
	return table.concat(t)
end

local function dump_state(tag)
	ensure_outdir()
	local machine = manager.machine
	local cpu = machine.devices[":maincpu"]
	local f = assert(io.open(OUTDIR .. "/dump_" .. tag .. ".txt", "w"))
	f:write("tag=" .. tag .. "\n")
	f:write("time=" .. tostring(machine.time:as_double()) .. "\n")

	if cpu then
		local st = cpu.state
		local names = {
			"PC", "SP", "AF", "BC", "DE", "HL", "IX", "IY",
			"IFF1", "IFF2", "IM", "HALT", "I",
			"PG0", "PG1", "PG2", "PG3", "PORT_Y", "RGMOD", "CNF"
		}
		for _, n in ipairs(names) do
			local ok, ent = pcall(function() return st[n] end)
			if ok and ent then
				f:write(string.format("%s=%s\n", n, tostring(ent.value)))
			end
		end

		local mem = cpu.spaces["program"]
		if mem then
			-- Known latches from current fuzix.map
			local panic_ptr = mem:read_u16(0xFD92)
			f:write(string.format("panic_ptr=%04X panic=%s\n", panic_ptr, read_cstr(mem, panic_ptr, 40)))
			f:write(string.format("trace_last=%02X\n", mem:read_u8(0xFDB0)))
			f:write(string.format("nopen_stage=%02X name0=%02X char=%02X wd=%04X ninode=%04X\n",
				mem:read_u8(0xFDE9), mem:read_u8(0xFDEA), mem:read_u8(0xFDEB),
				mem:read_u16(0xFDEC), mem:read_u16(0xFDEE)))

			-- sprinter_dbg @ FE51
			f:write("sprinter_dbg:")
			for i = 0, 31 do
				f:write(string.format(" %02X", mem:read_u8(0xFE51 + i)))
			end
			f:write("\n")

			local regions = {
				{ 0xFD70, 0x100, "fd70" },
				{ 0xFE40, 0x80, "fe40" },
				{ 0xEF40, 0x100, "ef40" },
				{ 0x0000, 0x80, "lowpage" },
			}
			for _, r in ipairs(regions) do
				f:write(string.format("\n-- mem %s --\n", r[3]))
				f:write(hexdump(mem, r[1], r[2]))
				f:write("\n")
			end
		end
	end

	-- memory regions (for VRAM scrape)
	f:write("\n-- regions --\n")
	local okregs, regs = pcall(function() return machine.memory.regions end)
	if okregs and regs then
		for tag2, reg in pairs(regs) do
			f:write(string.format("%s size=%d\n", tostring(tag2), reg.size))
		end
	end

	local oksnap, errsnap = pcall(function()
		machine.video:snapshot()
	end)
	f:write("snapshot_ok=" .. tostring(oksnap) .. " err=" .. tostring(errsnap) .. "\n")

	local oksave, errsave = pcall(function()
		machine:save(OUTDIR .. "/state_" .. tag)
	end)
	f:write("save_ok=" .. tostring(oksave) .. " err=" .. tostring(errsave) .. "\n")

	f:close()
	print("FUZIX dump written: " .. OUTDIR .. "/dump_" .. tag .. ".txt")
end

emu.add_machine_reset_notifier(function()
	print(string.format("FUZIX mame_dump: dump@%.1fs exit@%.1fs out=%s", DUMP_AT, EXIT_AT, OUTDIR))
end)

emu.register_frame_done(function()
	local t = manager.machine.time:as_double()
	if (not dumped) and t >= DUMP_AT then
		dumped = true
		dump_state(string.format("%.0f", t))
	end
	if t >= EXIT_AT then
		manager.machine:exit()
	end
end)

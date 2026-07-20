-- Probe /init handoff: dump exec markers + low page + user page 0.
local OUTDIR = os.getenv("FUZIX_MAME_OUT") or "/Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/mame_out"
local DUMP_AT = tonumber(os.getenv("FUZIX_MAME_DUMP_AT") or "6")
local EXIT_AT = tonumber(os.getenv("FUZIX_MAME_EXIT_AT") or "7")
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

local function scrape_row(mem, row)
	local t = {}
	for col = 0, 79 do
		local addr = ((col + 1) | 0x80) * 1024 + 0x301 + row * 4
		local b = mem:read_u8(addr)
		if b >= 32 and b < 127 then
			t[#t + 1] = string.char(b)
		elseif b ~= 0 and b ~= 0x20 then
			t[#t + 1] = "."
		else
			t[#t + 1] = " "
		end
	end
	return table.concat(t):gsub("%s+$", "")
end

local function dump_now(tag)
	ensure_outdir()
	local machine = manager.machine
	local cpu = machine.devices[":maincpu"]
	local f = assert(io.open(OUTDIR .. "/" .. tag .. ".txt", "w"))
	local st = cpu.state
	local mem = cpu.spaces["program"]
	f:write(string.format("t=%.3f PC=%04X SP=%04X IFF1=%s\n",
		machine.time:as_double(),
		st["PC"].value, st["SP"].value, tostring(st["IFF1"].value)))
	local function pg(n)
		local ok, e = pcall(function() return st[n].value end)
		if ok then return e end
		return -1
	end
	f:write(string.format("PG=%02X/%02X/%02X/%02X\n", pg("PG0"), pg("PG1"), pg("PG2"), pg("PG3")))

	-- common latches (current map)
	f:write("dbg@FE56:")
	for i = 0, 31 do
		f:write(string.format(" %02X", mem:read_u8(0xFE56 + i)))
	end
	f:write("\n")
	f:write(string.format("exec_fail_stage=%02X err=%04X done=%04X count=%04X\n",
		mem:read_u8(0xFDBC), mem:read_u16(0xFDBD),
		mem:read_u16(0xFDCF), mem:read_u16(0xFDD1)))
	f:write(string.format("doexec arm=%02X seen=%02X expect=%04X isp=%04X call=%02X\n",
		mem:read_u8(0xFE3D), mem:read_u8(0xFE3E),
		mem:read_u16(0xFE41), mem:read_u16(0xFE43),
		mem:read_u8(0xFE4C)))
	f:write(string.format("u_page=%02X %02X %02X %02X u_insys=%02X\n",
		mem:read_u8(0xEE02), mem:read_u8(0xEE03),
		mem:read_u8(0xEE04), mem:read_u8(0xEE05),
		mem:read_u8(0xEE06)))
	f:write(string.format("rst38=%02X nullh=%02X nmi=%02X\n",
		mem:read_u8(0xFD9D), mem:read_u8(0xFDB7), mem:read_u8(0xFDB6)))

	f:write("\n-- low page (mapped) --\n")
	f:write(hexdump(mem, 0x0000, 0x180))
	f:write("\n\n-- stack --\n")
	local sp = st["SP"].value
	f:write(hexdump(mem, sp, 0x40))
	f:write("\n\n-- screen rows 5..8 --\n")
	-- VRAM scrape needs region; fall back to program space if mapped
	for row = 5, 8 do
		f:write(string.format("%02d|%s\n", row, scrape_row(mem, row)))
	end
	f:close()
	pcall(function() machine.video:snapshot() end)
end

emu.register_frame(function()
	local t = manager.machine.time:as_double()
	if (not dumped) and t >= DUMP_AT then
		dumped = true
		dump_now("exec_probe")
	end
	if t >= EXIT_AT then
		manager.machine:exit()
	end
end)

-- Focused Sprinter FUZIX probe: panic context + VRAM text scrape + i_tab/root.
local OUTDIR = os.getenv("FUZIX_MAME_OUT") or "/tmp/fuzix_mame"
local DUMP_AT = tonumber(os.getenv("FUZIX_MAME_DUMP_AT") or "8")
local EXIT_AT = tonumber(os.getenv("FUZIX_MAME_EXIT_AT") or "9")
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
		if b == 0 then break end
		if b >= 32 and b < 127 then t[#t+1] = string.char(b)
		else t[#t+1] = string.format("\\x%02X", b) end
	end
	return table.concat(t)
end

-- Sprinter text cell in emulator VRAM (from sprinter.cpp / platform sprvideo.s):
-- For screen B, PORT_Y = (col+1)|0x80 selects a "line"; character at Mode1.
-- Empirically FUZIX plot_char maps WIN2=page0x50 and writes 0x8301+row*4.
-- In physical VRAM share, page 0x50 is one of the VRAM pages. Try several
-- layouts and keep any that looks like ASCII bootmarks.
local function scrape_candidates(vram, f)
	f:write("-- vram size=" .. tostring(vram.bytes or vram.size or -1) .. "\n")
	local size = vram.bytes or vram.size
	-- Layout A: linear 80x32 at various bases, stride 2 (char+attr)
	for _, base in ipairs({0x0000, 0x300, 0x400, 0x800, 0xC00, 0x1000, 0x2000, 0x4000, 0x8000, 0xC000}) do
		local line = {}
		local printable = 0
		for col = 0, 79 do
			local addr = base + col * 2
			if addr < size then
				local ch = vram:read_u8(addr)
				if ch >= 32 and ch < 127 then
					line[#line+1] = string.char(ch)
					printable = printable + 1
				elseif ch == 0 then
					line[#line+1] = " "
				else
					line[#line+1] = "."
				end
			end
		end
		if printable >= 8 then
			f:write(string.format("A base=%04X p=%d [%s]\n", base, printable, table.concat(line)))
		end
	end
	-- Layout B: FUZIX cell formula transposed into page0 of VRAM:
	-- for each col, char at ((col+1)|0x80) related offset - unknown.
	-- Try: for row in 0..31, col in 0..79: addr = ((col+1)|0x80)*1024 + 0x301 + row*4
	-- or addr = col*0x400 + 0x301 + row*4
	local function try_grid(name, addrfn)
		local rows = {}
		local printable = 0
		for row = 0, 31 do
			local line = {}
			for col = 0, 79 do
				local addr = addrfn(col, row)
				local ch = 0
				if addr >= 0 and addr < size then
					ch = vram:read_u8(addr)
				end
				if ch >= 32 and ch < 127 then
					line[#line+1] = string.char(ch)
					printable = printable + 1
				elseif ch == 0 then
					line[#line+1] = " "
				else
					line[#line+1] = "."
				end
			end
			local s = table.concat(line):gsub("%s+$", "")
			if s:match("%S") then
				rows[#rows+1] = string.format("%02d|%s", row, s)
			end
		end
		if printable >= 16 then
			f:write(string.format("\n-- grid %s printable=%d --\n", name, printable))
			for _, r in ipairs(rows) do f:write(r .. "\n") end
		end
	end

	try_grid("col*1024+0x301+row*4", function(c,r) return c * 1024 + 0x301 + r * 4 end)
	try_grid("(c+1)*1024+0x301+row*4", function(c,r) return (c + 1) * 1024 + 0x301 + r * 4 end)
	try_grid("((c+1)|0x80)*1024+0x301+row*4", function(c,r) return (((c + 1) | 0x80) * 1024 + 0x301 + r * 4) end)
	try_grid("c*1024+0x300+1+row*4", function(c,r) return c * 1024 + 0x300 + 1 + r * 4 end)
	try_grid("page50ish: 0x14000+c*4+r", function(c,r) return 0x14000 + c * 128 + r end)
end

local function dump()
	ensure_outdir()
	local machine = manager.machine
	local cpu = machine.devices[":maincpu"]
	local mem = cpu.spaces["program"]
	local f = assert(io.open(OUTDIR .. "/probe.txt", "w"))
	f:write(string.format("time=%.3f PC=%04X SP=%04X HALT=%s\n",
		machine.time:as_double(), cpu.state["PC"].value, cpu.state["SP"].value,
		tostring(cpu.state["HALT"].value)))
	f:write(string.format("PG=%02X/%02X/%02X/%02X\n",
		cpu.state["PG0"].value & 0xFF, cpu.state["PG1"].value & 0xFF,
		cpu.state["PG2"].value & 0xFF, cpu.state["PG3"].value & 0xFF))

	local panic_ptr = mem:read_u16(0xFD92)
	f:write(string.format("panic=%04X '%s'\n", panic_ptr, read_cstr(mem, panic_ptr, 40)))

	-- root / root_dev / i_tab head
	local root_dev = mem:read_u16(0x10A0)
	local root = mem:read_u16(0x10A4)
	f:write(string.format("root_dev=%04X root=%04X\n", root_dev, root))
	f:write("-- i_tab[0..7] @16E8 (assume cinode ~0x40? dump 0x200 bytes) --\n")
	f:write(hexdump(mem, 0x16E8, 0x200))
	f:write("\n")

	-- udata key fields: need offsets. Dump first 0x80 of udata @ EE00
	f:write("-- udata@EE00 --\n")
	f:write(hexdump(mem, 0xEE00, 0x80))
	f:write("\n")

	-- Try to locate u_insys/u_callno/u_cwd/u_root via map-relative known pattern.
	-- From kernel.h order after p_tab*: roughly early bytes. Also dump stack top.
	f:write(string.format("-- stack near SP=%04X --\n", cpu.state["SP"].value))
	local sp = cpu.state["SP"].value
	f:write(hexdump(mem, sp, 0x40))
	f:write("\n")

	-- shares
	f:write("-- shares --\n")
	local ok, shares = pcall(function() return machine.memory.shares end)
	if ok and shares then
		for tag, sh in pairs(shares) do
			local sz = sh.bytes or sh.size or -1
			f:write(string.format("%s size=%s\n", tostring(tag), tostring(sz)))
		end
		local vram = shares[":vram"] or shares["vram"]
		if not vram then
			for tag, sh in pairs(shares) do
				if tostring(tag):find("vram") then vram = sh break end
			end
		end
		if vram then
			scrape_candidates(vram, f)
		else
			f:write("NO vram share\n")
		end
	else
		f:write("no shares: " .. tostring(shares) .. "\n")
	end

	pcall(function() machine.video:snapshot() end)
	f:close()
	print("probe written")
	manager.machine:exit()
end

emu.register_frame_done(function()
	local t = manager.machine.time:as_double()
	if (not dumped) and t >= DUMP_AT then
		dumped = true
		dump()
	end
	if t >= EXIT_AT then
		manager.machine:exit()
	end
end)

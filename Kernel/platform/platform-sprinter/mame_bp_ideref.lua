-- Break on i_deref when argument looks like a small integer / bad pointer.
local OUT = os.getenv("FUZIX_MAME_OUT") or "/tmp/fuzix_mame"
local I_DEREF = 0x57D6
local dumped = false
local cpu, mem

local function hexdump(base, len)
	local lines = {}
	for i = 0, len - 1, 16 do
		local p = { string.format("%04X:", base + i) }
		for j = 0, 15 do
			if i + j < len then
				p[#p + 1] = string.format(" %02X", mem:read_u8(base + i + j))
			end
		end
		lines[#lines + 1] = table.concat(p)
	end
	return table.concat(lines, "\n")
end

local function on_break()
	if dumped then return end
	-- SDCC sdcccall(0): after call, SP points at return addr; arg at SP+2 (or SP+4 with push af)
	local sp = cpu.state["SP"].value
	local ret = mem:read_u16(sp)
	local a0 = mem:read_u16(sp + 2)
	local a1 = mem:read_u16(sp + 4)
	local a2 = mem:read_u16(sp + 6)
	-- Only care about clearly bogus inode pointers
	local arg = a0
	if a0 > 0x100 and a1 < 0x100 then
		arg = a1 -- push-af frame
	end
	if arg >= 0x100 and arg ~= 0x0001 then
		-- resume: not the bad call
		return
	end
	dumped = true
	os.execute("mkdir -p '" .. OUT .. "'")
	local f = assert(io.open(OUT .. "/ideref_hit.txt", "w"))
	f:write(string.format("PC=%04X SP=%04X ret=%04X a0=%04X a1=%04X a2=%04X chosen=%04X\n",
		cpu.state["PC"].value, sp, ret, a0, a1, a2, arg))
	f:write(string.format("PG=%02X/%02X/%02X/%02X HL=%04X DE=%04X BC=%04X IX=%04X IY=%04X\n",
		cpu.state["PG0"].value & 0xFF, cpu.state["PG1"].value & 0xFF,
		cpu.state["PG2"].value & 0xFF, cpu.state["PG3"].value & 0xFF,
		cpu.state["HL"].value, cpu.state["DE"].value, cpu.state["BC"].value,
		cpu.state["IX"].value, cpu.state["IY"].value))
	f:write("-- stack --\n")
	f:write(hexdump(sp, 0x40))
	f:write("\n-- udata cwd/root area --\n")
	f:write(hexdump(0xEE80, 0x30))
	f:write("\n")
	f:close()
	print("IDEREF HIT written")
	-- take screenshot via vram grid quickly
	manager.machine:exit()
end

emu.add_machine_reset_notifier(function()
	cpu = manager.machine.devices[":maincpu"]
	mem = cpu.spaces["program"]
	-- MAME debugger breakpoint via debug interface
	local dbg = manager.machine.debugger
	if dbg then
		dbg.console:execute(string.format("bpset %04X,1,{printf \"ideref\";g}", I_DEREF))
		print("bpset via debugger console")
	else
		print("no debugger; using PC poll")
	end
end)

-- Fallback: poll PC
emu.register_frame_done(function()
	if dumped then return end
	cpu = manager.machine.devices[":maincpu"]
	mem = cpu.spaces["program"]
	local pc = cpu.state["PC"].value
	if pc == I_DEREF or pc == I_DEREF + 1 then
		local sp = cpu.state["SP"].value
		local a0 = mem:read_u16(sp + 2)
		local a1 = mem:read_u16(sp + 4)
		local arg = a0
		if a0 > 0x0100 and a1 < 0x0100 then arg = a1 end
		if arg < 0x0100 then
			on_break()
		end
	end
	if manager.machine.time:as_double() > 20 then
		manager.machine:exit()
	end
end)

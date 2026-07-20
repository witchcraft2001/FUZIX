-- Dump PID1 write/syscall state after userland entry
-- Addresses from Kernel/fuzix.map (2026-07-20, dosys ABI fix, size 114)
local OUTDIR = os.getenv("FUZIX_MAME_OUT") or "."
local DUMP_AT = tonumber(os.getenv("FUZIX_MAME_DUMP_AT") or "5.5")
local EXIT_AT = tonumber(os.getenv("FUZIX_MAME_EXIT_AT") or "7")
local dumped = false

local DBG = 0xFEDF
local FAIL_STAGE = 0xFE45
local INITIO_STAGE = 0xFE77
local INITIO_FILES = 0xFE79
local INITIO_FD = 0xFE7A
local INITIO_ERR = 0xFE7C
local DOEXEC_SEEN = 0xFEC7
local DOEXEC_EXPECT = 0xFECA
local DOEXEC_ISP = 0xFECC
local RST38_COUNT = 0xFE26
local RST38_RET = 0xFE29
local RST38_CALLNO = 0xFE2C
local OFT = 0x15E2
local ITAB = 0x1762
local UDATA = 0xEE00
local U_FILES = UDATA + 0x7D
-- sprinit_raw (a_base=1, size 114): spr_stage@0x016C spr_wr@0x016F spr_spin@0x0171
local SPR_STAGE = 0x016C
local SPR_WR = 0x016F
local SPR_SPIN = 0x0171
local MSG = 0x0153

emu.register_frame(function()
	local t = manager.machine.time:as_double()
	if (not dumped) and t >= DUMP_AT then
		dumped = true
		local cpu = manager.machine.devices[":maincpu"]
		local mem = cpu.spaces["program"]
		local st = cpu.state
		local iosp = cpu.spaces["io"]
		if iosp then
			iosp:write_u8(0x82, 0x48)
			iosp:write_u8(0xA2, 0x49)
			iosp:write_u8(0xC2, 0x4A)
		end
		local f = assert(io.open(OUTDIR .. "/write.txt", "w"))
		local function rb(a) return mem:read_u8(a) end
		local function rw(a) return rb(a) + 256 * rb(a + 1) end
		f:write(string.format("t=%.2f PC=%04X SP=%04X HALT=%s PG=%s/%s/%s/%s\n",
			t, st["PC"].value, st["SP"].value, tostring(st["HALT"].value),
			tostring(st["PG0"].value), tostring(st["PG1"].value),
			tostring(st["PG2"].value), tostring(st["PG3"].value)))
		f:write(string.format("u_insys=%02X callno=%02X err=%04X retval=%04X\n",
			rb(UDATA + 0x06), rb(UDATA + 0x07), rw(UDATA + 0x0C), rw(UDATA + 0x0A)))
		f:write(string.format("argn=%04X %04X %04X\n",
			rw(UDATA + 0x12), rw(UDATA + 0x14), rw(UDATA + 0x16)))
		f:write(string.format("u_files=%02X %02X %02X %02X\n",
			rb(U_FILES), rb(U_FILES + 1), rb(U_FILES + 2), rb(U_FILES + 3)))
		f:write(string.format("initio stage=%02X fd=%04X err=%04X files=%02X %02X %02X\n",
			rb(INITIO_STAGE), rw(INITIO_FD), rw(INITIO_ERR),
			rb(INITIO_FILES), rb(INITIO_FILES + 1), rb(INITIO_FILES + 2)))
		f:write(string.format("fail_stage=%02X doexec seen=%02X expect=%04X isp=%04X\n",
			rb(FAIL_STAGE), rb(DOEXEC_SEEN), rw(DOEXEC_EXPECT), rw(DOEXEC_ISP)))
		f:write(string.format("rst38 count=%02X ret=%04X callno=%02X\n",
			rb(RST38_COUNT), rw(RST38_RET), rb(RST38_CALLNO)))
		f:write(string.format("spr_stage=%02X spr_wr=%04X spr_spin=%02X\n",
			rb(SPR_STAGE), rw(SPR_WR), rb(SPR_SPIN)))
		f:write("msg:")
		for i = 0, 22 do
			f:write(string.format(" %02X", rb(MSG + i)))
		end
		f:write("\n")
		f:write("dbg:")
		for i = 0, 31 do
			f:write(string.format(" %02X", rb(DBG + i)))
		end
		f:write("\n")
		f:write("user0112:")
		for i = 0, 15 do
			f:write(string.format(" %02X", rb(0x0112 + i)))
		end
		f:write("\n")
		for e = 0, 2 do
			local b = OFT + e * 8
			local ino = rw(b + 4)
			f:write(string.format("oft[%d] ino=%04X acc=%02X refs=%02X\n",
				e, ino, rb(b + 6), rb(b + 7)))
			if ino ~= 0 then
				f:write(string.format("  ino magic=%04X mode=%04X c_dev=%04X\n",
					rw(ino), rw(ino + 6), rw(ino + 2)))
			end
		end
		f:write(string.format("itab0 magic=%04X mode=%04X\n",
			rw(ITAB), rw(ITAB + 6)))
		f:close()
	end
	if t >= EXIT_AT then
		manager.machine:exit()
	end
end)

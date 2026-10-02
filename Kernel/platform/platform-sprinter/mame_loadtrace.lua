-- Extend the read-only runtime probe with buffer/bounce observations.
local root = os.getenv("FUZIX_ROOT") or "."
local out = os.getenv("FUZIX_MAME_OUT") or root .. "/Images/sprinter/mame_out"
local symbols = {}
for line in io.lines(root .. "/Kernel/fuzix.map") do
    local addr, name = line:match("^%s+([%x]+)%s+([_%w]+)%s+")
    if addr then symbols[name] = tonumber(addr, 16) end
end
local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces.program
local ram
for name, index in pairs(manager.machine.devices[":ram"].items) do
    if name:match("m_pointer$") then ram = emu.item(index) end
end
assert(ram)
local log = assert(io.open(out .. "/loadtrace.txt", "w"))
local tmp = assert(symbols._sprinter_exec_tmp)
local bounce = assert(symbols._sprinter_exec_bounce)
local pool = assert(symbols._bufpool)
local dbg = assert(symbols._sprinter_dbg)
local function kb(a) return ram:read(0x48 * 0x4000 + a) end
local function kw(a) return kb(a) + 256 * kb(a + 1) end
local function prefix(a)
    local s = {}
    for i = 0, 15 do s[#s + 1] = string.format("%02X", kb(a + i)) end
    return table.concat(s, " ")
end
local function record(event, foff)
    if kb(symbols._spr_doexec_count) ~= 1 then return end
    log:write(string.format("%s PC=%04X SP=%04X foff=%04X got=%04X n=%04X map=%02X %02X %02X bounce=%s\n",
        event, cpu.state.PC.value, cpu.state.SP.value, foff, kw(tmp + 2), kw(tmp + 6),
        kb(symbols.mpgsel_cache), kb(symbols.mpgsel_cache + 1),
        kb(symbols.mpgsel_cache + 2), prefix(bounce)))
    for i = 0, 4 do
        local bp = pool + i * 520
        log:write(string.format(" buf=%04X dev=%04X blk=%04X dirty=%02X busy=%02X data=%s\n",
            bp, kw(bp + 512), kw(bp + 514), kb(bp + 516), kb(bp + 517), prefix(bp)))
    end
    log:flush()
end
local taps
emu.register_frame(function()
    if taps then return end
    taps = {}
    taps[#taps + 1] = mem:install_write_tap(0x10000 + dbg + 2, 0x10000 + dbg + 2, "load-copy", function(addr, data)
        if data == 0xB1 then record("copy", kw(tmp + 4)) end
    end)
    taps[#taps + 1] = mem:install_write_tap(0x10000 + dbg + 4, 0x10000 + dbg + 4, "load-block", function(addr, data)
        record(string.format("bread=%04X", kb(dbg + 3) + 256 * data), kw(tmp + 4))
    end)
    for _, name in ipairs({"_bdread", "_td_read", "_ide_xfer", "_ide_read", "_ide_write", "_sprinter_bootmark", "_plot_char", "_devide_read_data", "__bank_2_1", "___sdcc_call_hl"}) do
        local addr = assert(symbols[name])
        taps[#taps + 1] = mem:install_read_tap(0x10000 + addr, 0x10000 + addr, "load-entry-" .. name, function(a, data)
            if kw(tmp + 4) ~= 0x2400 or kb(symbols._spr_doexec_count) ~= 1 or cpu.state.PC.value ~= addr then return end
            log:write(string.format("entry %s HL=%04X DE=%04X IX=%04X IY=%04X SP=%04X stack=%s\n",
                name, cpu.state.HL.value, cpu.state.DE.value, cpu.state.IX.value, cpu.state.IY.value,
                cpu.state.SP.value, prefix(cpu.state.SP.value)))
            log:flush()
        end)
    end
    taps[#taps + 1] = mem:install_write_tap(0x10000 + symbols._kernel_pages + 1, 0x10000 + symbols._kernel_pages + 2, "load-bank", function(a, data)
        if kw(tmp + 4) == 0x2400 and kb(symbols._spr_doexec_count) == 1 then
            log:write(string.format("bank PC=%04X addr=%04X value=%02X HL=%04X SP=%04X stack=%s\n",
                cpu.state.PC.value, a & 0xFFFF, data, cpu.state.HL.value, cpu.state.SP.value, prefix(cpu.state.SP.value)))
            log:flush()
        end
    end)
end)
dofile(root .. "/Kernel/platform/platform-sprinter/mame_runtime.lua")

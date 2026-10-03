-- Observe fork with hardware mappings and physical RAM reads only.
local root = os.getenv("FUZIX_ROOT") or "."
local out = os.getenv("FUZIX_MAME_OUT") or root .. "/Images/sprinter/mame_out"
local stop_time = tonumber(os.getenv("FUZIX_MAME_STOP")) or 25
local followup = os.getenv("FUZIX_MAME_FOLLOW") or "set{ENTER}"
local follow_time = tonumber(os.getenv("FUZIX_MAME_FOLLOW_TIME")) or 18
local symbols = {}
for line in io.lines(root .. "/Kernel/fuzix.map") do
    local addr, name = line:match("^%s+([%x]+)%s+([_%w]+)%s+")
    if addr then symbols[name] = tonumber(addr, 16) end
end
local cpu = manager.machine.devices[":maincpu"]
local log = assert(io.open(out .. "/fork.txt", "w"))
local ram, hw, regs, pg3
for tag, device in pairs(manager.machine.devices) do
    for name, index in pairs(device.items) do
        if tag == ":ram" and name:match("m_pointer$") then ram = emu.item(index) end
        if name:match("/m_ram_pages$") then regs = emu.item(index) end
        if name:match("/m_pg3$") then pg3 = emu.item(index) end
        if name:match("/m_pages$") then
            log:write("hardware map item: " .. tag .. " " .. name .. "\n")
            hw = emu.item(index)
        end
    end
end
assert(ram and hw and regs and pg3, "RAM/hardware map save items not found")
log:write(string.format("map item size=%d count=%d\n", hw.size, hw.count))
local function page(i) return hw:read(i) & 0xFF end
local function rb(a) return ram:read(page(a >> 14) * 0x4000 + (a & 0x3FFF)) end
local function rw(a) return rb(a) + 256 * rb(a + 1) end
local function bytes(a, n)
    local s = {}
    for i = 0, n - 1 do s[#s + 1] = string.format("%02X", rb(a + i)) end
    return table.concat(s, " ")
end
local function record(event)
    local st, ud = cpu.state, assert(symbols._udata)
    log:write(string.format("%s t=%.6f PC=%04X SP=%04X HL=%04X DE=%04X BC=%04X hw=%02X %02X %02X %02X up=%s usp=%04X ptab=%04X stack=%s\n",
        event, manager.machine.time:as_double(), st.PC.value, st.SP.value,
        st.HL.value, st.DE.value, st.BC.value, page(0), page(1), page(2), page(3),
        bytes(ud + 2, 4), rw(ud + 14), rw(ud), bytes(st.SP.value, 24)))
    log:write(string.format("registers=%02X %02X %02X %02X\n", regs:read(0x28), regs:read(0x29), regs:read(0x2A), regs:read(pg3:read(0))))
    log:flush()
end
local taps, armed, saved, followed
emu.register_frame(function()
    local t = manager.machine.time:as_double()
    if t < 7 then return end
    if armed and not followed and t >= follow_time and not manager.machine.natkeyboard.is_posting then
        followed = true
        log:write("followup: " .. followup .. "\n")
        manager.machine.natkeyboard:post_coded(followup)
    end
    if not taps then
        taps = {}
        local dcp = assert(io.open(out .. "/fork-dcp-entry.bin", "wb"))
        dcp:write(ram:read_block(0x40 * 0x4000, 0x4000))
        dcp:close()
        local addr = assert(symbols._dofork)
        taps[#taps + 1] = cpu.spaces.program:install_read_tap(0x10000 + addr, 0x10000 + addr, "fork-entry", function()
            if cpu.state.PC.value ~= addr then return end
            armed = true
            record("dofork")
        end)
        for _, name in ipairs({"_makeproc", "_getproc", "_switchin", "_plt_switchout", "_panic", "_i_deref"}) do
            local pc = assert(symbols[name])
            local bank = name == "_i_deref" and 0x4E or 0x4C
            taps[#taps + 1] = cpu.spaces.program:install_read_tap(0x10000 + pc, 0x10000 + pc, "fork-" .. name, function()
                if armed and cpu.state.PC.value == pc and (pc >= 0xC000 or page(1) == bank) then record(name) end
            end)
        end
        for line in io.lines(root .. "/Kernel/platform/platform-sprinter/tricks.rst") do
            local a, label = line:match("^%s+([%x]+)%s+%d+%s+(fork_[%w_]+):")
            if a then
                local pc = tonumber(a, 16)
                taps[#taps + 1] = cpu.spaces.program:install_read_tap(0x10000 + pc, 0x10000 + pc, "fork-" .. label, function()
                    if armed and cpu.state.PC.value == pc then record(label) end
                end)
            end
        end
    end
    local ud = assert(symbols._udata)
    local proc = rw(ud)
    local state = ram:read(0x48 * 0x4000 + proc)
    local released = rw(ud + 2) == 0xFFFF and rw(ud + 4) == 0xFFFF and
        rb(ud + 6) == 1 and proc >= assert(symbols._ptab) and proc < 0x4000 and
        (state == 7 or (state == 1 and rb(ud + 7) == 0))
    local invalid = armed and not released and (rb(ud + 2) < 8 or rb(ud + 2) >= 0x40)
    local idle_halt = symbols.spr_idle_halt
    local idle = idle_halt and (cpu.state.PC.value == idle_halt or cpu.state.PC.value == idle_halt + 1)
    if not saved and ((cpu.state.HALT.value ~= 0 and not idle) or invalid or t >= stop_time) then
        saved = true
        record("stop")
        for p = 0x30, 0x4F do
            local f = assert(io.open(string.format("%s/fork-page-%02X.bin", out, p), "wb"))
            f:write(ram:read_block(p * 0x4000, 0x4000))
            f:close()
        end
        log:close()
        for _, tap in ipairs(taps) do tap:remove() end
    end
end)
dofile(root .. "/Kernel/platform/platform-sprinter/mame_console.lua")

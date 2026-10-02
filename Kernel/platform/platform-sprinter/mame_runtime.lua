-- Read-only runtime trace. Resolve symbols from this build, never remap RAM.
local root = os.getenv("FUZIX_ROOT") or "."
local out = os.getenv("FUZIX_MAME_OUT") or root .. "/Images/sprinter/mame_out"
local symbols = {}
for line in io.lines(root .. "/Kernel/fuzix.map") do
    local addr, name = line:match("^%s+([%x]+)%s+([_%w]+)%s+")
    if addr then symbols[name] = tonumber(addr, 16) end
end
local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]
local ud = assert(symbols._udata)
local dex = assert(symbols._spr_doexec_count)
-- This latch aliases other bring-up probes; it is not a reliable panic flag.
local trace_alias = assert(symbols._sprinter_last_panic_ptr)
local mp = assert(symbols.mpgsel_cache)
local kp = assert(symbols._kernel_pages)
local f = assert(io.open(out .. "/runtime.txt", "w"))
-- A failed /init run must not leave a snapshot from an older successful exec.
assert(io.open(out .. "/runtime-memory.bin", "wb")):close()
assert(io.open(out .. "/runtime-entry.bin", "wb")):close()
local ram
for name, index in pairs(manager.machine.devices[":ram"].items) do
    if name:match("m_pointer$") then ram = emu.item(index) end
end
assert(ram, "Sprinter RAM save item not found")
local pages
-- Address-space reads invoke Sprinter wait/accelerator handlers, even from
-- Lua. Common/stack RAM stays on page 4B; MPGSEL cache lives there too.
local function rb(a)
    a = a & 0xFFFF
    local page = a >= 0xC000 and 0x4B or ram:read(0x4B * 0x4000 + (mp & 0x3FFF) + (a >> 14))
    return ram:read(page * 0x4000 + (a & 0x3FFF))
end
local function rw(a) return rb(a) + 256 * rb(a + 1) end
local function bytes(a, n)
    local s = {}
    for i = 0, n - 1 do s[#s + 1] = string.format("%02X", rb(a + i)) end
    return table.concat(s, " ")
end
local last = ""
local tap
local exec_tap
local function save_user(path, map)
    local snapshot = assert(io.open(path, "wb"))
    for _, page in ipairs(map) do
        snapshot:write(ram:read_block(page * 0x4000, 0x4000))
    end
    snapshot:close()
end
local function trace_write(addr, data)
    if rb(dex) < 2 then return end
    f:write(string.format("write t=%.6f PC=%04X SP=%04X addr=%04X data=%02X up=%s mp=%s call=%02X\n",
        manager.machine.time:as_double(), cpu.state.PC.value, cpu.state.SP.value,
        addr, data, bytes(ud + 2, 4), bytes(mp, 4), rb(ud + 7)))
    if (addr & 0xFFFF) == ud + 6 and (data == 0 or data == 1) then
        local sp = data == 1 and cpu.state.SP.value or rw(ud + 8)
        f:write(string.format("sys %s call=%02X retpc=%04X args=%s rv=%04X err=%04X\n",
            data == 1 and "enter" or "leave", rb(ud + 7), rw(sp + 12),
            bytes(ud + 18, 8), rw(ud + 10), rw(ud + 12)))
        if data == 1 and rb(ud + 7) == 8 then
            local base, count = rw(ud + 20), math.min(rw(ud + 22), 80)
            local s = {}
            for i = 0, count - 1 do
                local a = (base + i) & 0xFFFF
                local c = a >= 0xC000 and rb(a) or ram:read(rb(ud + 2 + (a >> 14)) * 0x4000 + (a & 0x3FFF))
                s[#s + 1] = c >= 32 and c < 127 and string.char(c) or "."
            end
            f:write("write text=" .. table.concat(s) .. "\n")
        end
    end
    f:flush()
end
emu.register_frame(function()
    local t = manager.machine.time:as_double()
    if t >= 7 and not tap then
        -- Sprinter's Z84C015 adds bit 16 for normal memory cycles.
        tap = mem:install_write_tap(0x10000 + ud + 2, 0x10000 + ud + 13, "runtime", trace_write)
        exec_tap = mem:install_write_tap(0x10000 + dex, 0x10000 + dex, "exec-entry", function(addr, data)
            if data == 2 then
                save_user(out .. "/runtime-entry.bin", {rb(ud + 2), rb(ud + 3), rb(ud + 4), rb(mp + 3)})
                f:write("snapshot saved before second doexec enters userspace\n")
                f:flush()
            end
        end)
    end
    if t < 7 then return end
    local st = cpu.state
    local valid = true
    for i = 0, 2 do
        if rb(ud + 2 + i) < 8 or rb(ud + 2 + i) >= 0x48 then valid = false end
    end
    if rb(dex) == 2 and valid then
        pages = {rb(ud + 2), rb(ud + 3), rb(ud + 4), rb(mp + 3)}
    end
    local corrupt = rb(dex) >= 2 and not valid
    local key = bytes(ud + 6, 2) .. bytes(trace_alias, 2) .. tostring(st.HALT.value)
    if key ~= last or t >= 25 then
        last = key
        f:write(string.format("t=%.3f PC=%04X SP=%04X HALT=%s dex=%02X insys=%02X call=%02X err=%04X arg=%04X brk=%04X up=%s mp=%s kp=%s trace_alias=%04X\n",
            t, st.PC.value, st.SP.value, tostring(st.HALT.value), rb(dex),
            rb(ud + 6), rb(ud + 7), rw(ud + 12), rw(ud + 18), rw(ud + 30),
            bytes(ud + 2, 4), bytes(mp, 4), bytes(kp, 3), rw(trace_alias)))
        f:flush()
    end
    if st.HALT.value ~= 0 or corrupt or t >= 25 then
        if tap then tap:remove() end
        if exec_tap then exec_tap:remove() end
        f:write("stop=" .. (corrupt and "invalid user pages" or st.HALT.value ~= 0 and "HALT" or "time limit") .. "\n")
        f:write("dbg=" .. bytes(assert(symbols._sprinter_dbg), 16) .. "\n")
        f:write("stack=" .. bytes(st.SP.value, 64) .. "\n")
        for _, name in ipairs({"AF", "BC", "DE", "HL", "IX", "IY", "I", "IM", "IFF1", "IFF2"}) do
            if st[name] then f:write(string.format("reg %s=%04X\n", name, st[name].value)) end
        end
        for _, name in ipairs({"_udata", "mpgsel_cache", "_kernel_pages", "_spr_doexec_count", "_sprinter_rst38_count", "_sprinter_rst38_ret", "_sprinter_dbg"}) do
            f:write(string.format("symbol %s=%04X\n", name, assert(symbols[name])))
        end
        if ram then
            if pages then
                save_user(out .. "/runtime-memory.bin", pages)
                f:write(string.format("snapshot pages=%02X %02X %02X %02X (last valid user map, live common)\n", table.unpack(pages)))
            end
            for row = 0, 31 do
                local s = {}
                for col = 0, 79 do
                    local c = ram:read(0x50 * 0x4000 + (col + 0x81) * 1024 + 0x301 + row * 4)
                    s[#s + 1] = c >= 32 and c < 127 and string.char(c) or "."
                end
                f:write(string.format("screen%02d=%s\n", row, table.concat(s)))
            end
        end
        for name, addr in pairs(symbols) do
            if name:match("^_spr_gi") then
                f:write(string.format("%s@%04X=%s\n", name, addr, bytes(addr, 2)))
            end
        end
        f:close()
        manager.machine:exit()
    end
end)

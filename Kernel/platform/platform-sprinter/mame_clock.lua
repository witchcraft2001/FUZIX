-- Observe IRQ scheduling and map restoration without device reads or remapping RAM.
local root = os.getenv('FUZIX_ROOT') or '.'
local out = os.getenv('FUZIX_MAME_OUT') or root .. '/Images/sprinter/mame_out'
local syms = {}
for line in io.lines(root .. '/Kernel/fuzix.map') do
    local a, n = line:match('^%s+([%x]+)%s+([_%w]+)%s+')
    if a then syms[n] = tonumber(a, 16) end
end
local cpu = manager.machine.devices[':maincpu']
local ram, hw
for name, index in pairs(manager.machine.devices[':ram'].items) do
    if name:match('m_pointer$') then ram = emu.item(index) end
end
for name, index in pairs(manager.machine.devices[':'].items) do
    if name:match('/m_pages$') then hw = emu.item(index) end
end
assert(ram and hw and hw.count == 4, 'Sprinter RAM/hardware map not found')
local function rb(a) return ram:read((hw:read(a >> 14) & 255) * 0x4000 + (a & 0x3fff)) end
local function kw(a) return ram:read(0x48 * 0x4000 + a) + 256 * ram:read(0x48 * 0x4000 + a + 1) end
local f = assert(io.open(out .. '/clock.txt', 'w'))
local taps, irqs, timers, last = {}, 0, 0, -1
local user, kernel, preempt, restores, bad = 0, 0, 0, 0, 0
local active, idle, temporary, vram, cachebad = 0, 0, 0, 0, 0
local iffchecks, iffbad, return_taps, frames = 0, 0, {}, {}
local saved
emu.register_frame(function()
    local t = manager.machine.time:as_double()
    if t < 7 then return end
    if #taps == 0 then
        local irq = syms._spr_irq_gate or (syms._spr_doexec and assert(syms.interrupt_handler)) or
            rb(0xe1e2) + 256 * rb(0xe1e3)
        taps[1] = cpu.spaces.program:install_read_tap(0x10000 + irq, 0x10000 + irq, 'clock-irq', function()
            if cpu.state.PC.value == irq then irqs = irqs + 1 end
        end)
        local addr = assert(syms._timer_interrupt)
        taps[2] = cpu.spaces.program:install_read_tap(0x10000 + addr, 0x10000 + addr, 'clock-tick', function()
            if cpu.state.PC.value == addr and (hw:read(1) & 255) == 0x4c then timers = timers + 1 end
        end)
        if syms.spr_map_return then
            local enter, leave = assert(syms.map_save_kernel), syms.spr_map_return
            taps[3] = cpu.spaces.program:install_read_tap(0x10000 + enter, 0x10000 + enter, 'irq-map-save', function()
                if cpu.state.PC.value ~= enter then return end
                saved = {context = rb(syms._udata + 6), time = manager.machine.time:as_double()}
                for i = 0, 2 do
                    saved[i + 1] = hw:read(i) & 255
                    saved[i + 4] = rb(syms._kernel_pages + i)
                    if saved[i + 1] ~= rb(syms.mpgsel_cache + i) then
                        cachebad = cachebad + 1
                        f:write(string.format('IRQ cache mismatch at t=%.6f window=%d hw=%02X cache=%02X\n',
                            saved.time, i, saved[i + 1], rb(syms.mpgsel_cache + i)))
                    end
                end
                if saved[1] == 0x48 then kernel = kernel + 1 else user = user + 1 end
                if saved.context ~= 0 then
                    if syms._spr_idle_irq and rb(syms._spr_idle_irq) ~= 0 then
                        idle = idle + 1
                    else
                        active = active + 1
                        if saved[2] ~= saved[5] or saved[3] ~= saved[6] then temporary = temporary + 1 end
                        if saved[3] == 0x50 then vram = vram + 1 end
                    end
                end
            end)
            taps[4] = cpu.spaces.program:install_read_tap(0x10000 + leave, 0x10000 + leave, 'irq-map-restore', function()
                if cpu.state.PC.value ~= leave then return end
                restores = restores + 1
                local ok = saved ~= nil
                for i = 0, 2 do
                    ok = ok and saved[i + 1] == (hw:read(i) & 255) and
                        saved[i + 4] == rb(syms._kernel_pages + i)
                end
                if not ok then
                    bad = bad + 1
                    local actual = {}
                    for i = 0, 2 do
                        actual[i + 1] = hw:read(i) & 255
                        actual[i + 4] = rb(syms._kernel_pages + i)
                    end
                    f:write(string.format('IRQ map mismatch at t=%.6f insys=%d saved=%s actual=%s\n',
                        manager.machine.time:as_double(), saved and saved.context or -1,
                        saved and table.concat(saved, ',') or 'missing', table.concat(actual, ',')))
                end
                saved = nil
            end)
            local pc = assert(syms.preemption)
            taps[5] = cpu.spaces.program:install_read_tap(0x10000 + pc, 0x10000 + pc, 'irq-preempt', function()
                if cpu.state.PC.value == pc then preempt = preempt + 1 end
            end)
        end
        for _, name in ipairs({'banksetbc', 'map_kernel', 'map_for_swap', '_devide_read_data', '_devide_write_data'}) do
            local addr = syms[name]
            if addr then
                taps[#taps + 1] = cpu.spaces.program:install_read_tap(0x10000 + addr, 0x10000 + addr, 'iff-' .. name, function()
                    if cpu.state.PC.value ~= addr or (addr < 0x4000 and (hw:read(0) & 255) ~= 0x48) then return end
                    local sp = cpu.state.SP.value
                    local ret = rb(sp) + 256 * rb((sp + 1) & 0xffff)
                    local window, page = ret >> 14, hw:read(ret >> 14) & 255
                    if name == 'banksetbc' and (window == 1 or window == 2) then
                        local bc = cpu.state.BC.value
                        page = window == 1 and (bc & 255) or (bc >> 8)
                    elseif name == 'map_kernel' and window < 3 then
                        page = window == 0 and 0x48 or rb(syms._kernel_pages + window)
                    end
                    frames[#frames + 1] = {sp = (sp + 2) & 0xffff, ret = ret,
                        page = page, iff = cpu.state.IFF2.value, name = name}
                    if not return_taps[ret] then
                        return_taps[ret] = cpu.spaces.program:install_read_tap(0x10000 + ret, 0x10000 + ret, 'iff-return', function()
                            if cpu.state.PC.value ~= ret then return end
                            for i = #frames, 1, -1 do
                                local call = frames[i]
                                if call.ret == ret and call.sp == cpu.state.SP.value and call.page == (hw:read(ret >> 14) & 255) then
                                    iffchecks = iffchecks + 1
                                    if call.iff ~= cpu.state.IFF1.value then
                                        iffbad = iffbad + 1
                                        f:write(string.format('IFF mismatch at t=%.6f helper=%s ret=%04X expected=%d actual=%d\n',
                                            manager.machine.time:as_double(), call.name, ret, call.iff, cpu.state.IFF1.value))
                                    end
                                    table.remove(frames, i)
                                    break
                                end
                            end
                        end)
                    end
                end)
            end
        end
    end
    local sec = math.floor(t)
    if sec ~= last then
        last = sec
        f:write(string.format('t=%.6f irq=%d timer=%d ticks=%d ds=%d PC=%04X HALT=%d IFF1=%d user=%d kernel=%d preempt=%d maps=%d bad=%d active=%d idle=%d temp=%d vram=%d cachebad=%d iffchecks=%d iffbad=%d iffpend=%d\n',
            t, irqs, timers, kw(syms._ticks), kw(syms._ticks_this_dsecond) & 255,
            cpu.state.PC.value, cpu.state.HALT.value, cpu.state.IFF1.value,
            user, kernel, preempt, restores, bad, active, idle, temporary, vram, cachebad, iffchecks, iffbad, #frames))
        f:flush()
    end
end)
dofile(root .. '/Kernel/platform/platform-sprinter/mame_fork.lua')

-- Send builtin commands through MAME's emulated PS/2 keyboard.
local root = os.getenv("FUZIX_ROOT") or "."
local out = os.getenv("FUZIX_MAME_OUT") or root .. "/Images/sprinter/mame_out"
local sent = false
local command = os.getenv("FUZIX_MAME_COMMAND") or "set{ENTER}"
local input = assert(io.open(out .. "/console-scancodes.txt", "w"))
local cpu = manager.machine.devices[":maincpu"]
local symbols = {}
for line in io.lines(root .. "/Kernel/fuzix.map") do
    local addr, name = line:match("^%s+([%x]+)%s+([_%w]+)%s+")
    if addr then symbols[name] = tonumber(addr, 16) end
end
local ram
for name, index in pairs(manager.machine.devices[":ram"].items) do
    if name:match("m_pointer$") then ram = emu.item(index) end
end
assert(ram, "Sprinter RAM save item not found")
local rx
local tty
emu.register_frame(function()
    if sent or manager.machine.time:as_double() < 13 then return end
    sent = true
    rx = cpu.spaces["io"]:install_read_tap(0, 0xFFFF, "console-rx", function(addr, data)
        if (addr & 0xFF) == 0x18 then
            input:write(string.format("t=%.6f PC=%04X data=%02X\n",
                manager.machine.time:as_double(), cpu.state.PC.value, data))
            input:flush()
        end
    end)
    local pc = assert(symbols._tty_inproc)
    tty = cpu.spaces["program"]:install_read_tap(0x10000 + pc, 0x10000 + pc, "console-tty", function()
        if cpu.state.PC.value ~= pc then return end
        local sp = cpu.state.SP.value
        -- Bring-up keeps the live stack on 4B and kernel data on 48.
        local stack = 0x4B * 0x4000 + (sp & 0x3FFF)
        local flags = 0x48 * 0x4000 + assert(symbols._ttydata) + 32 + 4
        input:write(string.format("tty t=%.6f char=%02X iflag=%02X%02X lflag=%02X%02X\n",
            manager.machine.time:as_double(), ram:read(stack + 5),
            ram:read(flags + 1), ram:read(flags), ram:read(flags + 7), ram:read(flags + 6)))
        input:flush()
    end)
    local keyboard = manager.machine.natkeyboard
    local found = false
    for _, device in pairs(keyboard.keyboards) do
        device.enabled = device.tag:find("kbd", 1, true) ~= nil
        found = found or device.enabled
    end
    assert(found, "PS/2 keyboard input device not found")
    local f = assert(io.open(out .. "/console-input.txt", "w"))
    f:write(keyboard:dump())
    f:write("\nposted: " .. command .. "\n")
    f:close()
    keyboard:post_coded(command)
end)
dofile(root .. "/Kernel/platform/platform-sprinter/mame_runtime.lua")

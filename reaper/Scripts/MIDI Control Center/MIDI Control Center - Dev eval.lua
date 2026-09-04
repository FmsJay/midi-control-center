-- Oxygen Pro 61: development hook. Runs as a defer loop and executes any Lua file dropped at
--   Scripts/MIDI Control Center/midi_control_center/dev/eval.lua
-- inside REAPER, writing whatever the chunk returns (or the error) to dev/result.txt and deleting the input.
-- Used to test the editor and apply logic without restarting REAPER. Harmless when the folder is empty.
-- Stop it with the action's toggle (run it again) or by closing REAPER.

local res = reaper.GetResourcePath()
local DIR = res .. "/Scripts/MIDI Control Center/midi_control_center/dev"
local IN, OUT = DIR .. "/eval.lua", DIR .. "/result.txt"
reaper.RecursiveCreateDirectory(DIR, 0)

local function write(path, s)
    local f = io.open(path, "w")
    if f then f:write(s); f:close() end
end
local function serialise(v, depth)
    depth = depth or 0
    if type(v) ~= "table" then return tostring(v) end
    if depth > 4 then return "{...}" end
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. serialise(x, depth + 1) end
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
end

local running = true
local _, _, section, cmd = reaper.get_action_context()
if cmd and cmd > 0 then reaper.SetToggleCommandState(section, cmd, 1); reaper.RefreshToolbar2(section, cmd) end
reaper.atexit(function()
    if cmd and cmd > 0 then reaper.SetToggleCommandState(section, cmd, 0); reaper.RefreshToolbar2(section, cmd) end
end)

local function tick()
    local f = io.open(IN, "r")
    if f then
        local code = f:read("*a"); f:close()
        os.remove(IN)
        local chunk, err = load(code, "dev eval", "t")
        local out
        if not chunk then out = "COMPILE ERROR: " .. tostring(err)
        else
            local ok, r1, r2 = pcall(chunk)
            if ok then out = "OK\n" .. serialise(r1) .. (r2 ~= nil and ("\n" .. serialise(r2)) or "")
            else out = "RUNTIME ERROR: " .. tostring(r1) end
        end
        write(OUT, out)
    end
    if running then reaper.defer(tick) end
end
reaper.ShowConsoleMsg("[oxygen] dev eval hook watching " .. IN .. "\n")
tick()

-- Oxygen Pro 61 + ReaLearn: first-time setup for a new machine (or after REAPER's MIDI device numbers changed)
--
-- What it does by itself:
--   1. finds the keyboard's REAPER MIDI device numbers by name (they differ per machine),
--   2. rewrites Helgoboss/ReaLearn/controllers.json so ReaLearn creates the Oxygen unit(s) automatically,
--   3. rewrites the drum-injection device number inside presets/main/oxygen-pro-61/live.preset.luau,
--   4. makes sure Helgobox (ReaLearn) sits in the MONITORING FX chain and opens it,
--   5. opens Preferences and prints the exact boxes that only a human can tick.
-- Then restart REAPER. Everything else (presets, watcher, scripts) already lives in this portable install.

local res = reaper.GetResourcePath()
-- optional extra devices: the MIDI interface the FCB1010 is plugged into (name pattern, Lua plain find) and the Exquis
local FCB_INPUT_MATCH = "UR22"
local EXQUIS_NAME = "Exquis"
local function log(s) reaper.ShowConsoleMsg(s .. "\n") end
reaper.ShowConsoleMsg("")
log("=== Oxygen Pro 61 first-time setup ===")

-- 1. device numbers ------------------------------------------------------------------------------
local function find_in(name)
  for i = 0, reaper.GetNumMIDIInputs() - 1 do
    local ok, n = reaper.GetMIDIInputNameNoAlias(i, "")
    if ok and n == name then return i end
  end
end
local function find_out(name)
  for i = 0, reaper.GetNumMIDIOutputs() - 1 do
    local ok, n = reaper.GetMIDIOutputNameNoAlias(i, "")
    if ok and n == name then return i end
  end
end
local function find_in_match(pattern)
  for i = 0, reaper.GetNumMIDIInputs() - 1 do
    local ok, n = reaper.GetMIDIInputNameNoAlias(i, "")
    if ok and n:find(pattern, 1, true) then return i, n end
  end
end
local in3  = find_in("MIDIIN3 (Oxygen Pro 61)")
local in1  = find_in("Oxygen Pro 61")
local out3 = find_out("MIDIOUT3 (Oxygen Pro 61)")
if not (in3 and in1 and out3) then
  log("Keyboard not fully visible to REAPER. Found: MIDIIN3=" .. tostring(in3) .. " port1=" .. tostring(in1) .. " MIDIOUT3=" .. tostring(out3))
  log("Plug the Oxygen Pro 61 in, wait a few seconds, then run this again.")
  return
end
log(string.format("Devices: MIDIIN3 = input %d, Oxygen Pro 61 (port 1) = input %d, MIDIOUT3 = output %d", in3, in1, out3))

-- 2. controllers.json -----------------------------------------------------------------------------
local ctl_path = res .. "/Helgoboss/ReaLearn/controllers.json"
local fcb_in, fcb_name = find_in_match(FCB_INPUT_MATCH)
local exq_in, exq_out = find_in(EXQUIS_NAME), find_out(EXQUIS_NAME)
local extra = ""
if fcb_in then
  extra = extra .. string.format([[,
    {
      "id": "fcb1010-shift",
      "name": "FCB1010 hold shift (via %s)",
      "enabled": true,
      "connection": { "kind": "Midi", "input_port": %d },
      "default_main_preset": "fcb1010/shift"
    }]], fcb_name, fcb_in)
  log(string.format("FCB1010 interface '%s' = input %d", fcb_name, fcb_in))
else
  log("No MIDI input matching '" .. FCB_INPUT_MATCH .. "': FCB1010 unit not added (edit FCB_INPUT_MATCH at the top if needed)")
end
if exq_in and exq_out then
  extra = extra .. string.format([[,
    {
      "id": "exquis",
      "name": "Exquis (Developer Mode)",
      "enabled": true,
      "connection": { "kind": "Midi", "input_port": %d, "output_port": %d },
      "default_main_preset": "exquis/main"
    }]], exq_in, exq_out)
  log(string.format("Exquis = input %d, output %d", exq_in, exq_out))
else
  log("Exquis not found as both input and output: Exquis unit not added")
end
local ctl = string.format([[{
  "controllers": [
    {
      "id": "oxygen-pro-61-live",
      "name": "Oxygen Pro 61 Live mode (port 3)",
      "enabled": true,
      "connection": { "kind": "Midi", "input_port": %d, "output_port": %d },
      "default_main_preset": "oxygen-pro-61/live"
    },
    {
      "id": "oxygen-pro-61-pads",
      "name": "Oxygen Pro 61 Preset-mode pads (port 1)",
      "enabled": true,
      "connection": { "kind": "Midi", "input_port": %d, "output_port": %d },
      "default_main_preset": "oxygen-pro-61/pads"
    }%s
  ]
}
]], in3, out3, in1, out3, extra)
local f = io.open(ctl_path, "w")
if f then f:write(ctl); f:close(); log("Wrote " .. ctl_path) else log("Could not write " .. ctl_path) end

-- 3. drum injection device inside the live preset ------------------------------------------------------
local preset_path = res .. "/Data/helgoboss/realearn/presets/main/oxygen-pro-61/live.preset.luau"
local pf = io.open(preset_path, "r")
if pf then
  local src = pf:read("*a"); pf:close()
  local new, n = src:gsub("local PORT1_INPUT_DEVICE = %d+", "local PORT1_INPUT_DEVICE = " .. in1)
  if n > 0 then
    local wf = io.open(preset_path, "w"); wf:write(new); wf:close()
    log("Set drum-injection device to input " .. in1 .. " in live.preset.luau")
  else
    log("Warning: PORT1_INPUT_DEVICE line not found in live.preset.luau")
  end
else
  log("Warning: " .. preset_path .. " not found")
end

-- 3b. device numbers inside the FCB1010 bridge and Exquis presets -------------------------------------------
local function patch(path, pattern, repl, label)
  local pf = io.open(path, "r")
  if not pf then return end
  local src = pf:read("*a"); pf:close()
  local new, n = src:gsub(pattern, repl)
  if n > 0 then local wf = io.open(path, "w"); wf:write(new); wf:close(); log("Set " .. label) end
end
local fcb_preset = res .. "/Data/helgoboss/realearn/presets/main/fcb1010/shift.preset.luau"
patch(fcb_preset, "local MIDIIN3_DEVICE = %d+", "local MIDIIN3_DEVICE = " .. in3, "MIDIIN3 device in fcb1010/shift")
patch(fcb_preset, "local EXQUIS_DEVICE = [%w]+", "local EXQUIS_DEVICE = " .. (exq_in and tostring(exq_in) or "nil"), "Exquis device in fcb1010/shift")
patch(res .. "/Data/helgoboss/realearn/presets/main/exquis/main.preset.luau", "local PORT1_INPUT_DEVICE = %d+", "local PORT1_INPUT_DEVICE = " .. in1, "port-1 device in exquis/main")

-- 4. Helgobox in the monitoring FX chain --------------------------------------------------------------------
local master = reaper.GetMasterTrack(0)
local NAME = "Helgobox - ReaLearn & Playtime"
local idx = reaper.TrackFX_AddByName(master, NAME, true, 0)
if idx < 0 then idx = reaper.TrackFX_AddByName(master, NAME, true, 1) end
if idx < 0 then
  log("Could not add '" .. NAME .. "' to the monitoring FX chain. Is Helgobox installed (UserPlugins/reaper_helgobox-x64.dll)?")
else
  reaper.TrackFX_Show(master, 0x1000000 + idx, 3)
  log("Helgobox is in the monitoring FX chain (slot " .. (idx + 1) .. ") and its window is open.")
end

-- 5. register the editor and the watcher as actions (so they appear in the Actions list without a manual Load) ----
for _, name in ipairs({ "Oxygen Pro - Editor.lua", "Oxygen Pro - Live watcher.lua", "Oxygen Pro - LED unlock.lua", "Exquis - Developer mode off.lua" }) do
  local path = res .. "/Scripts/Oxygen Pro/" .. name
  local f = io.open(path, "r")
  if f then
    f:close()
    local cmd = reaper.AddRemoveReaScript(true, 0, path, true)
    log(cmd ~= 0 and ("Registered action: " .. name) or ("Could not register " .. name))
  end
end

-- 6. the human part --------------------------------------------------------------------------------------------
log("")
log("Now tick these (the API cannot):")
log("  Preferences > MIDI Devices:")
log("    'MIDIIN3 (Oxygen Pro 61)'  -> enable input for CONTROL MESSAGES only (not as a track input)")
log("    'Oxygen Pro 61'            -> enable input + control")
log("    'MIDIOUT3 (Oxygen Pro 61)' -> enable output")
log("    leave MIDIIN2/MIDIIN4/MIDIOUT2/MIDIOUT4 disabled")
log("  Preferences > Control/OSC/web: remove any Mackie Control Universal / HUI entry using the Oxygen ports")
log("  ReaLearn window: Menu > Instance > 'Enable global control'")
log("Then restart REAPER. The Live watcher in __startup.lua puts the keyboard into Live mode and unlocks the LEDs.")
log("Reference: Utility/oxygen-pro-tools/LIVE_MODE_MAP.md and oxygen_live_map.html")
reaper.ViewPrefs(0, "MIDI Devices")

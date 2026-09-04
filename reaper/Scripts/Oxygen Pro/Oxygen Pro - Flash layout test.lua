-- Oxygen Pro 61: one-shot test of the pad colour sweep, independent of the watcher.
-- Sweeps green across the 16 pads over ~0.7 s, then asks ReaLearn to repaint the real colours.
-- If this works but the DAW button does not trigger a sweep, the watcher's input detection is at fault;
-- if this does nothing, the output path (MIDIOUT3 enabled as output?) is at fault.
local OUT_NAME = "MIDIOUT3 (Oxygen Pro 61)"
local PAD_NOTE = { 40, 41, 42, 43, 48, 49, 50, 51, 36, 37, 38, 39, 44, 45, 46, 47 }
local out
for i = 0, reaper.GetNumMIDIOutputs() - 1 do
  local ok, name = reaper.GetMIDIOutputNameNoAlias(i, "")
  if ok and name == OUT_NAME then out = i end
end
if not out then reaper.ShowConsoleMsg("Flash test: " .. OUT_NAME .. " not found\n") return end
local steps, t0, k = {}, reaper.time_precise(), 1
local function tick()
  local now = reaper.time_precise()
  if k <= 16 and now >= t0 + k * 0.045 then
    reaper.SendMIDIMessageToHardware(out, string.char(0x90, PAD_NOTE[k], 12), 3)
    k = k + 1
  end
  if k > 16 and now >= t0 + 16 * 0.045 + 0.4 then
    local cmd = reaper.NamedCommandLookup("_REALEARN_SEND_ALL_FEEDBACK")
    if cmd ~= 0 then reaper.Main_OnCommand(cmd, 0) end
    reaper.ShowConsoleMsg("Flash test: sweep sent on output " .. out .. ", ReaLearn asked to repaint\n")
    return
  end
  reaper.defer(tick)
end
tick()

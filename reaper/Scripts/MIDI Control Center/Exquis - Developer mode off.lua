-- Exquis: hand the encoders, slider and buttons back to the firmware (leave Developer Mode).
-- Run this if the Exquis buttons stop responding after REAPER closed without unloading ReaLearn,
-- or before opening the Exquis app. Sends F0 00 21 7E 7F 00 00 F7 to the "Exquis" output.

local function find_output(name)
  for i = 0, reaper.GetNumMIDIOutputs() - 1 do
    local ok, n = reaper.GetMIDIOutputNameNoAlias(i, "")
    if ok and n == name then return i end
  end
end
local out = find_output("Exquis")
if not out then
  reaper.ShowConsoleMsg("[exquis] output 'Exquis' not found (enable it in Preferences > MIDI Devices)\n")
  return
end
local msg = string.char(0xF0, 0x00, 0x21, 0x7E, 0x7F, 0x00, 0x00, 0xF7)
reaper.SendMIDIMessageToHardware(out, msg, #msg)
reaper.ShowConsoleMsg("[exquis] Developer Mode off (all zones back to the firmware)\n")

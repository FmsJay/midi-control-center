-- Oxygen Pro 61: put DAW-mode button LEDs under software control so REAPER's
-- Mackie Control surface (output MIDIOUT3) can light rec/select/mute/solo.
-- Runs the python sender out-of-process, so it never fights REAPER for the port.
-- Run this after re-plugging or power-cycling the keyboard. See
-- DAW/Utility/oxygen-pro-tools/oxygen_led_unlock.py for the sysex itself.
-- Paths use forward slashes: Lua treats a backslash as an escape character.
local res = reaper.GetResourcePath()
local root = res:match("^(.*)[/\\]REAPER$")
if not root then
  reaper.ShowConsoleMsg("Oxygen LED unlock: unexpected resource path " .. res .. "\n")
  return
end
local script = root .. "/Utility/oxygen-pro-tools/oxygen_led_unlock.py"
local py = "C:/Python314/python.exe"
local f = io.open(py, "r")
if f then f:close() else py = "python" end
local out = reaper.ExecProcess('"' .. py .. '" "' .. script .. '"', 5000)
reaper.ShowConsoleMsg(((out or "ExecProcess failed"):gsub("^%d+\n", "")) .. "\n")

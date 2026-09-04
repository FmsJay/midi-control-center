-- Exquis: capture the keyboard's current layout + MIDI settings as a Developer-Mode snapshot and store it next to
-- the editor (midi_control_center/exquis_snapshot.txt). From then on every Apply embeds it in the Exquis preset, and
-- the ReaLearn unit restores it each time it loads (REAPER start, Apply), so the Exquis always comes up in the
-- layout you captured. Run again to overwrite; delete the file to stop restoring.
--
-- Set the layout you want on the Exquis first (or in the Exquis app, then close the app and reconnect), then run this.
-- Needs the Exquis enabled as REAPER input and output; the reply arrives within a second.

local res = reaper.GetResourcePath()
local OUT_PATH = res .. "/Scripts/MIDI Control Center/midi_control_center/exquis_snapshot.txt"
local function log(s) reaper.ShowConsoleMsg("[exquis] " .. s .. "\n") end

local out
for i = 0, reaper.GetNumMIDIOutputs() - 1 do
  local ok, n = reaper.GetMIDIOutputNameNoAlias(i, "")
  if ok and n == "Exquis" then out = i end
end
if not out then log("output 'Exquis' not found (enable it in Preferences > MIDI Devices)"); return end

-- Developer Mode must be on for cmd 09; enabling the encoder zone only is harmless (the unit re-sends its own mask)
local function send(t) local s = string.char(table.unpack(t)); reaper.SendMIDIMessageToHardware(out, s, #s) end
send({ 0xF0, 0x00, 0x21, 0x7E, 0x7F, 0x00, 0x2E, 0xF7 })
send({ 0xF0, 0x00, 0x21, 0x7E, 0x7F, 0x09, 0xF7 })

local last_seq, t0 = nil, reaper.time_precise()
local function poll()
  local newest
  for i = 0, 63 do
    local seq, buf = reaper.MIDI_GetRecentInputEvent(i)
    if not seq or seq == 0 then break end
    if last_seq and seq <= last_seq then break end
    if newest == nil then newest = seq end
    if last_seq and #buf >= 8 and buf:byte(1) == 0xF0 and buf:sub(2, 6) == string.char(0x00, 0x21, 0x7E, 0x7F, 0x09) then
      local body = buf:sub(7, -1)
      if body:byte(-1) == 0xF7 then body = body:sub(1, -2) end
      local hex = {}
      for b = 1, #body do hex[#hex + 1] = string.format("%02X", body:byte(b)) end
      local f = io.open(OUT_PATH, "w")
      f:write("# Exquis snapshot captured " .. os.date("%Y-%m-%d %H:%M") .. " (" .. #body .. " bytes)\n" .. table.concat(hex, " ") .. "\n")
      f:close()
      log(string.format("snapshot captured (%d bytes) -> %s. Apply from the editor to embed it.", #body, OUT_PATH))
      return
    end
  end
  if newest then last_seq = newest end
  if last_seq == nil then last_seq = 0 end
  if reaper.time_precise() - t0 < 3 then reaper.defer(poll) else log("no snapshot reply within 3 s (is the Exquis input enabled and Developer Mode available?)") end
end
poll()

-- Oxygen Pro 61 - Live watcher (pure ReaScript, no Python needed)
--
-- 1. Keeps the keyboard in its Ableton "Live" firmware mode with software-controlled LEDs, which it
--    forgets whenever it is powered off. Every 2 s it checks whether "MIDIOUT3 (Oxygen Pro 61)" is
--    present; when the keyboard (re)appears it waits for it to boot, sends the three M-Audio sysex
--    messages, flashes the layout colour across the pads, then asks ReaLearn to repaint everything.
-- 3. Back layer: ReaLearn echoes CC 104 (127 armed / 0 dropped) into port 1; the pads switch to a violet/rose
--    checkerboard while the layer is armed and repaint when it is consumed or cancelled.
-- 4. Bank: ReaLearn echoes Bank < / > (CC 110 / 111) into port 1; pad 1-4 flashes white for the new bank number.
-- 2. Watches the DAW button (CC 113 on port 3, which ReaLearn uses to toggle the layout) and answers
--    each press with a one-second colour sweep across the pads so you can see which layout is active:
--    in the layout's colour (read from the preset's sweep_colour fields). The screen cannot be written to in this mode.
--
-- Runs as a background defer loop (started from __startup.lua with dofile, or run once from the Actions
-- list). Needs MIDIOUT3 enabled as an output and MIDIIN3 enabled for control in Preferences > MIDI Devices.
-- Prints one line to the ReaScript console when it starts, arms the keyboard, or sees a layout press.

local OUT_NAME   = "MIDIOUT3 (Oxygen Pro 61)"
local RESYNC_CMD = "_REALEARN_SEND_ALL_FEEDBACK"   -- Helgobox/ReaLearn: Send feedback for all instances
local POLL_SEC, BOOT_SEC = 2.0, 1.5
local LAYOUT_CC  = 113                              -- DAW button in Live mode (any device, channel 1)
local BACK_CC    = 104                              -- Back layer echo from ReaLearn: 127 = armed, 0 = consumed / cancelled
local BACK_PATTERN = { 50, 35 }                     -- Back layer: violet / rose checkerboard, painted at once
local BANK_CC_DOWN, BANK_CC_UP = 110, 111           -- Bank < / > echoes from ReaLearn (only while the Back layer is off)
local BANK_COLOUR, BANK_FLASH_SEC = 63, 0.45         -- pad 1-4 lights white for the newly selected bank
local COLOUR_CODE = { off = 0, red = 3, orange = 11, green = 12, chartreuse = 14, yellow = 15, rose = 35,
                      aqua = 44, blue = 48, violet = 50, magenta = 51, azure = 56, cyan = 60, white = 63 }
local LAYOUT_COLOUR = { [0] = 12 }                  -- filled from the preset's layouts (sweep_colour), default green
local PRESET_PATH = reaper.GetResourcePath() .. "/Data/helgoboss/realearn/presets/main/oxygen-pro-61/live.preset.luau"
-- the generated preset lists every layout with a sweep_colour; read them so the sweep matches the editor's model
local function load_layout_colours()
  local f = io.open(PRESET_PATH, "r")
  if not f then return end
  local src = f:read("*a"); f:close()
  local found, i = {}, 0
  for name in src:gmatch('sweep_colour%s*=%s*"(%a+)"') do found[i] = COLOUR_CODE[name] or 12; i = i + 1 end
  if i > 0 then LAYOUT_COLOUR = found end
end
load_layout_colours()
local PAD_NOTE = { 40, 41, 42, 43, 48, 49, 50, 51, 36, 37, 38, 39, 44, 45, 46, 47 }

local function log(s) reaper.ShowConsoleMsg("[oxygen] " .. s .. "\n") end

-- SDP-120 number entry: the piano's ReaLearn unit echoes typed tone numbers as a CC; this module performs them
local SDP = nil
do
  package.path = reaper.GetResourcePath() .. "/Scripts/MIDI Control Center/midi_control_center/?.lua;" .. package.path
  local ok, mod = pcall(require, "sdp120_numbers")
  if ok then SDP = mod; local loaded, why = SDP.load(); log(loaded and "SDP-120 number entry armed" or ("SDP-120 number entry off (" .. tostring(why) .. ")"))
  else log("sdp120_numbers module not loaded: " .. tostring(mod)) end
end

-- only one watcher at a time: starting a newer copy (after editing this file) retires the running one
local GEN_KEY = "OxygenPro61Watcher"
local my_gen = (tonumber(reaper.GetExtState(GEN_KEY, "gen")) or 0) + 1
reaper.SetExtState(GEN_KEY, "gen", tostring(my_gen), false)

local function bytes(t)
  local s = {}
  for i, b in ipairs(t) do s[i] = string.char(b) end
  return table.concat(s)
end
local HDR = { 0xF0, 0x00, 0x01, 0x05, 0x7F, 0x00, 0x00 }
local function sysex(cmd, val)
  local t = {}
  for i, b in ipairs(HDR) do t[i] = b end
  t[#t + 1] = cmd; t[#t + 1] = 0x00; t[#t + 1] = 0x01; t[#t + 1] = val; t[#t + 1] = 0xF7
  return bytes(t)
end
local UNLOCK = {                      -- {delay after previous step, message}
  { 0.00, sysex(0x6D, 2) },           -- firmware mode = Live
  { 0.20, sysex(0x6B, 1) },           -- LED control enable
  { 0.10, sysex(0x6C, 3) },           -- LED mode = software
}

local function find_output()
  for i = 0, reaper.GetNumMIDIOutputs() - 1 do
    local ok, name = reaper.GetMIDIOutputNameNoAlias(i, "")
    if ok and name == OUT_NAME then return i end
  end
  return nil
end

local out_idx, present = nil, false
local queue = {}                      -- pending steps { at, msg } or { at, resync = true }, kept sorted by time
local next_poll = 0
local layout = 0                      -- mirrors ReaLearn's layout parameter (both start at 0, step + wrap on CC 113)
local bank = 0                        -- mirrors ReaLearn's bank parameter 0-3 (clamped, no wrap, like the preset)
local last_seq = nil

local function enqueue(at, entry)
  entry.at = at
  local i = #queue
  while i >= 1 and queue[i].at > at do i = i - 1 end
  table.insert(queue, i + 1, entry)
end

-- a colour sweep over the 16 pads (top row left to right, then bottom row), held briefly, then repaint
local function flash(now, colour)
  local t = now
  for k = 1, 16 do
    t = t + 0.045
    enqueue(t, { msg = bytes({ 0x90, PAD_NOTE[k], colour }) })
  end
  enqueue(t + 0.35, { resync = true })
end

-- Back layer armed: paint the whole grid in the checkerboard at once (no sweep); dropped: repaint immediately
local function paint_back_layer(now)
  queue = {}
  for k = 1, 16 do
    local row, col = (k - 1) // 8, (k - 1) % 8
    enqueue(now, { msg = bytes({ 0x90, PAD_NOTE[k], BACK_PATTERN[(row + col) % 2 + 1] }) })
  end
end
local function repaint(now) enqueue(now, { resync = true }) end

-- Bank change: light the pad with the bank's number for a moment, then repaint
local function flash_bank(now)
  enqueue(now, { msg = bytes({ 0x90, PAD_NOTE[bank + 1], BANK_COLOUR }) })
  enqueue(now + BANK_FLASH_SEC, { resync = true })
end

local function arm(now)
  queue = {}
  local t = now + BOOT_SEC
  for _, step in ipairs(UNLOCK) do
    t = t + step[1]
    enqueue(t, { msg = step[2] })
  end
  flash(t + 0.3, LAYOUT_COLOUR[layout])
  log("keyboard present on output " .. tostring(out_idx) .. "; arming Live mode + LEDs")
end

-- Tap tempo: ReaLearn echoes each encoder press as CC 102 into the port-1 input. Two or more taps
-- within TAP_WINDOW seconds set REAPER's tempo to the average interval, rounded to whole BPM.
local TAP_CC, TAP_WINDOW, TAP_MIN_BPM, TAP_MAX_BPM = 102, 2.0, 30, 300
local taps = {}
local function tap(now)
  if #taps > 0 and now - taps[#taps] > TAP_WINDOW then taps = {} end
  taps[#taps + 1] = now
  if #taps > 8 then table.remove(taps, 1) end
  if #taps >= 2 then
    local bpm = 60 * (#taps - 1) / (taps[#taps] - taps[1])
    if bpm >= TAP_MIN_BPM and bpm <= TAP_MAX_BPM then
      bpm = math.floor(bpm + 0.5)
      reaper.SetCurrentBPM(0, bpm, true)
      log(string.format("tap tempo: %d taps -> %d BPM", #taps, bpm))
    end
  end
end

-- Exquis: leaving its on-device Settings menu resets every LED (it announces this with sysex F0 00 21 7E 7F 03 ...).
-- Re-arm Developer Mode for the non-pad zones and ask ReaLearn to repaint shortly after.
local EXQUIS_REFRESH = string.char(0xF0, 0x00, 0x21, 0x7E, 0x7F, 0x03)
local function exquis_output()
  for i = 0, reaper.GetNumMIDIOutputs() - 1 do
    local ok, name = reaper.GetMIDIOutputNameNoAlias(i, "")
    if ok and name == "Exquis" then return i end
  end
end
local exquis_repaint_at = nil
local function exquis_refresh_seen(now, buf)
  -- entering the menu sends 03 7F; only repaint on the way out (anything else, or no page byte)
  local page = buf:byte(7)
  if page == 0x7F then return end
  exquis_repaint_at = now + 0.3
end
local function exquis_repaint(now)
  if not exquis_repaint_at or now < exquis_repaint_at then return end
  exquis_repaint_at = nil
  local out = exquis_output()
  if out then
    local m = string.char(0xF0, 0x00, 0x21, 0x7E, 0x7F, 0x00, 0x2E, 0xF7)
    reaper.SendMIDIMessageToHardware(out, m, #m)
  end
  local cmd = reaper.NamedCommandLookup(RESYNC_CMD)
  if cmd ~= 0 then reaper.Main_OnCommand(cmd, 0) end
  log("Exquis left its settings menu; repainted")
end

-- DAW button: CC 113 with a non-zero value on channel 1, from any control-enabled device.
local function poll_layout_button(now)
  local newest = nil
  for i = 0, 63 do
    local seq, buf = reaper.MIDI_GetRecentInputEvent(i)
    if not seq or seq == 0 or not buf or buf == "" then break end
    if last_seq and seq <= last_seq then break end
    if newest == nil then newest = seq end
    if last_seq and #buf >= 6 and buf:sub(1, 6) == EXQUIS_REFRESH then exquis_refresh_seen(now, buf) end
    if last_seq and #buf >= 3 then
      local status, d1, d2 = buf:byte(1, 3)
      if status == 0xB0 and d1 == LAYOUT_CC and d2 > 0 then
        load_layout_colours()
        local n = 0
        for _ in pairs(LAYOUT_COLOUR) do n = n + 1 end
        layout = (layout + 1) % math.max(1, n)
        flash(now, LAYOUT_COLOUR[layout] or 12)
        log("layout press seen -> layout " .. (layout + 1) .. " of " .. n)
      elseif status == 0xB0 and d1 == TAP_CC and d2 > 0 then
        tap(now)
      elseif status == 0xB0 and d1 == BACK_CC then
        if d2 > 0 then paint_back_layer(now); log("Back layer armed")
        else repaint(now); log("Back layer dropped") end
      elseif SDP and SDP.handle(status, d1, d2) then
        -- SDP-120 number echo performed
      elseif status == 0xB0 and (d1 == BANK_CC_DOWN or d1 == BANK_CC_UP) and d2 > 0 then
        bank = math.max(0, math.min(3, bank + (d1 == BANK_CC_UP and 1 or -1)))
        flash_bank(now)
      end
    end
  end
  if newest then last_seq = newest end
  if last_seq == nil then last_seq = 0 end   -- nothing in the buffer yet: start counting from here
end

local function tick()
  if (tonumber(reaper.GetExtState(GEN_KEY, "gen")) or my_gen) ~= my_gen then log("watcher generation " .. my_gen .. " retired"); return end
  local now = reaper.time_precise()
  if now >= next_poll then
    next_poll = now + POLL_SEC
    local idx = find_output()
    local now_present = idx ~= nil
    if now_present and not present then
      out_idx = idx
      arm(now)
    elseif not now_present and present then
      log("keyboard disconnected")
    end
    present = now_present
    if present then out_idx = idx end
  end
  if SDP then SDP.reload_if_changed() end
  poll_layout_button(now)
  exquis_repaint(now)
  while #queue > 0 and now >= queue[1].at do
    local step = table.remove(queue, 1)
    if step.resync then
      local cmd = reaper.NamedCommandLookup(RESYNC_CMD)
      if cmd ~= 0 then reaper.Main_OnCommand(cmd, 0) end
    elseif out_idx and step.msg then
      reaper.SendMIDIMessageToHardware(out_idx, step.msg, #step.msg)
    end
  end
  reaper.defer(tick)
end

log("Live watcher started")
tick()

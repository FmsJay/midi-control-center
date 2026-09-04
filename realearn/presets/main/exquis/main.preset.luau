--- name: Exquis - REAPER control (Developer Mode, pads stay MPE)
--- realearn_version: 2.18.0
--- author: Oxygen Pro 61 Rich REAPER Integration
--- description: |
---     Intuitive Instruments Exquis as a REAPER control surface, next to the Oxygen Pro 61.
---     Unit input AND output = the "Exquis" USB port (enable it as input + control + output in REAPER).
---     On load the unit puts the Exquis into Developer Mode for the encoders, slider, Up/Down and the six action
---     buttons (zone mask 2E); the pads are left native so they keep sending MPE notes on channels 2-15, which
---     pass through this unit untouched to your instrument tracks. Taken-over controls report on channel 16
---     (0-based 15); their LEDs are set with sysex F0 00 21 7E 7F 04 <id> r g b fx F7 (RGB 0-127).
---     Needs Exquis firmware >= 2.1 and the Exquis app CLOSED (it owns the port and repaints the LEDs).
---
---     Layout (SHIFT = the FCB1010 foot switch, injected here as CC 105 on channel 14 by the fcb1010/shift unit):
---       Play/Stop  play / stop (green)        shift: insert marker
---       Record     record (red)               shift: metronome on/off
---       Loop       repeat (yellow)            shift: show/hide mixer
---       Clips      insert marker (white)      shift: save project
---       Undo/Redo  undo / redo (violet)       shift: previous / next marker
---       Down/Up    previous / next track      shift: zoom out / in
---       Encoder 1  selected track volume      shift: master volume
---       Encoder 2  selected track pan         shift: selected track send 1
---       Encoder 3  browse tracks              shift: zoom out / in
---       Encoder 4  project tempo              shift: (free)
---       Encoder pushes 1-3: mute / solo / arm the selected track (LED shows state); push 4: tap tempo (Oxygen watcher)
---       Slider zones 1-6: go to marker 1-6 (orange)
---     Leave Developer Mode: run "Exquis - Developer mode off.lua" (or power-cycle the Exquis).

--!strict

local mappings = {}
local function add(m) table.insert(mappings, m) end

local CH = 15                                   -- Developer Mode reports on MIDI channel 16
local SHIFT_CC, SHIFT_CH = 105, 13              -- hold shift injected by the FCB1010 bridge unit (channel 14)
local PORT1_INPUT_DEVICE = 14                   -- "Oxygen Pro 61" input: the Live watcher listens there for tap tempo (B0 66 7F)

-- element ids (Developer Mode spec 2025-03-10)
local BTN = { record = 102, loop = 103, clips = 104, play = 105, down = 106, up = 107, undo = 108, redo = 109 }
local ENC = { 110, 111, 112, 113 }
local ENC_PUSH = { 114, 115, 116, 117 }
local SLIDER_LED = { 80, 81, 82, 83, 84, 85 }

-- ---- parameters --------------------------------------------------------------------------------
local P_SHIFT = 0
local parameters = {
    { index = P_SHIFT, id = "shift", name = "Shift (FCB1010 hold)", value_count = 2, value_labels = { "up", "held" } },
}
local SHIFT_UP   = { kind = "Modifier", modifiers = { { parameter = P_SHIFT, on = false } } }
local SHIFT_DOWN = { kind = "Modifier", modifiers = { { parameter = P_SHIFT, on = true } } }

-- ---- helpers ------------------------------------------------------------------------------------
local function cc_button(ch, n) return { kind = "MidiControlChangeValue", channel = ch, controller_number = n, character = "Button" } end
local function encoder(n)       return { kind = "MidiControlChangeValue", channel = CH, controller_number = n, character = "Relative2" } end
local function action(cmd)      return { kind = "ReaperAction", command = cmd, invocation = "Trigger" } end
local function param(i)         return { kind = "CompartmentParameterValue", parameter = { address = "ById", index = i } } end
local SELECTED = { address = "Selected" }
local MASTER   = { address = "Master" }
local PRESS    = { button_filter = "PressOnly" }
local TOGGLE   = { absolute_mode = "ToggleButton" }

-- RGB colours 0-127 per channel
local RGB = {
    green = { 0, 127, 0 }, red = { 127, 0, 0 }, yellow = { 127, 90, 0 }, violet = { 70, 0, 127 }, azure = { 0, 70, 127 },
    white = { 90, 90, 90 }, orange = { 127, 40, 0 }, cyan = { 0, 110, 110 }, magenta = { 127, 0, 100 }, off = { 0, 0, 0 },
}
local function dim(c) return { math.floor(c[1] / 6), math.floor(c[2] / 6), math.floor(c[3] / 6) } end
local function rgb_list(c) return c[1] .. ", " .. c[2] .. ", " .. c[3] end

-- Lua feedback script: paint one LED; y > 0 -> on colour, else off colour (both RGB tables)
local function led_script(id, on, off)
    return "local r, g, b = " .. rgb_list(off) .. "\n"
        .. "if y ~= nil and y > 0 then r, g, b = " .. rgb_list(on) .. " end\n"
        .. "return { address = " .. id .. ", messages = { { 0xF0, 0x00, 0x21, 0x7E, 0x7F, 0x04, " .. id .. ", r, g, b, 0x00, 0xF7 } } }"
end
-- a feedback-only mapping that paints `id` from the state of `target` (or a fixed colour when target is Dummy)
local function led(id, target, on, off, condition)
    add { id = "led-" .. id .. (condition == SHIFT_DOWN and "-shift" or ""), name = "LED " .. id, control_enabled = false,
          activation_condition = condition,
          source = { kind = "MidiScript", script_kind = "Lua", script = led_script(id, on, off or dim(on)) }, target = target }
end
local function paint(id, colour, condition)
    led(id, { kind = "Dummy" }, colour, colour, condition)
end

-- ---- Developer Mode on load ----------------------------------------------------------------------
-- fires once when the unit (and this always-active mapping) becomes active; the hook on deactivation hands the
-- controls back to the firmware when the unit unloads (belt and braces: the "Developer mode off" script does the same)
add { id = "devmode", name = "Exquis Developer Mode (encoders, slider, up/down, buttons)", control_enabled = false,
      source = { kind = "MidiScript", script_kind = "Lua",
                 script = "return { address = 0, messages = { { 0xF0, 0x00, 0x21, 0x7E, 0x7F, 0x00, 0x2E, 0xF7 } } }" },
      target = { kind = "Dummy" },
      on_deactivate = { send_midi_feedback = { { kind = "Raw", message = "F0 00 21 7E 7F 00 00 F7" } } } }

-- ---- shift (FCB1010 hold) ------------------------------------------------------------------------
add { id = "shift", name = "Shift held (FCB1010 via bridge)", feedback_enabled = false,
      source = cc_button(SHIFT_CH, SHIFT_CC), target = param(P_SHIFT) }

-- ---- transport buttons ---------------------------------------------------------------------------
local function button(id, elem, name, glue, target, on, off)
    add { id = id, name = name, feedback_enabled = false, activation_condition = SHIFT_UP,
          source = cc_button(CH, elem), glue = glue, target = target }
    if on then led(elem, target, on, off, SHIFT_UP) end
end
local function shifted(id, elem, name, command, colour)
    add { id = id, name = "Shift + " .. name, feedback_enabled = false, activation_condition = SHIFT_DOWN,
          source = cc_button(CH, elem), glue = PRESS, target = action(command) }
    if colour then paint(elem, colour, SHIFT_DOWN) end
end

button("play",   BTN.play,   "Play/Stop", TOGGLE, { kind = "TransportAction", action = "PlayStop" }, RGB.green)
button("record", BTN.record, "Record",    TOGGLE, { kind = "TransportAction", action = "Record" },   RGB.red)
button("loop",   BTN.loop,   "Repeat",    TOGGLE, { kind = "TransportAction", action = "Repeat" },   RGB.yellow)
button("clips",  BTN.clips,  "Insert marker (40157)", PRESS, action(40157))
paint(BTN.clips, RGB.white, SHIFT_UP)
button("undo",   BTN.undo,   "Undo (40029)", PRESS, action(40029))
button("redo",   BTN.redo,   "Redo (40030)", PRESS, action(40030))
paint(BTN.undo, RGB.violet, SHIFT_UP); paint(BTN.redo, RGB.violet, SHIFT_UP)
button("down",   BTN.down,   "Previous track (40286)", PRESS, action(40286))
button("up",     BTN.up,     "Next track (40285)",     PRESS, action(40285))
paint(BTN.down, RGB.azure, SHIFT_UP); paint(BTN.up, RGB.azure, SHIFT_UP)

shifted("shift-play",   BTN.play,   "Play = insert marker (40157)",     40157, RGB.white)
shifted("shift-record", BTN.record, "Record = metronome (40364)",       40364, RGB.magenta)
shifted("shift-loop",   BTN.loop,   "Loop = toggle mixer (40078)",      40078, RGB.cyan)
shifted("shift-clips",  BTN.clips,  "Clips = save project (40026)",     40026, RGB.green)
shifted("shift-undo",   BTN.undo,   "Undo = previous marker (40172)",   40172, RGB.orange)
shifted("shift-redo",   BTN.redo,   "Redo = next marker (40173)",       40173, RGB.orange)
shifted("shift-down",   BTN.down,   "Down = zoom out (1011)",           1011,  RGB.cyan)
shifted("shift-up",     BTN.up,     "Up = zoom in (1012)",              1012,  RGB.cyan)

-- ---- encoders --------------------------------------------------------------------------------------
add { id = "enc1", name = "Selected track volume", feedback_enabled = false, activation_condition = SHIFT_UP,
      source = encoder(ENC[1]), target = { kind = "TrackVolume", track = SELECTED } }
add { id = "enc2", name = "Selected track pan", feedback_enabled = false, activation_condition = SHIFT_UP,
      source = encoder(ENC[2]), target = { kind = "TrackPan", track = SELECTED } }
add { id = "enc3", name = "Browse tracks", feedback_enabled = false, activation_condition = SHIFT_UP,
      source = encoder(ENC[3]), target = { kind = "BrowseTracks", scroll_arrange_view = true, scroll_mixer = true } }
add { id = "enc4", name = "Project tempo", feedback_enabled = false, activation_condition = SHIFT_UP,
      source = encoder(ENC[4]), glue = { step_size_interval = { 0.001, 0.001 } }, target = { kind = "Tempo" } }
add { id = "shift-enc1", name = "Shift + encoder 1 = master volume", feedback_enabled = false, activation_condition = SHIFT_DOWN,
      source = encoder(ENC[1]), target = { kind = "TrackVolume", track = MASTER } }
add { id = "shift-enc2", name = "Shift + encoder 2 = selected track send 1", feedback_enabled = false, activation_condition = SHIFT_DOWN,
      source = encoder(ENC[2]), target = { kind = "RouteVolume", route = { address = "ByIndex", track = SELECTED, route_kind = "Send", index = 0 } } }
add { id = "shift-enc3-in",  name = "Shift + encoder 3 = zoom in (1012)",  feedback_enabled = false, activation_condition = SHIFT_DOWN,
      source = encoder(ENC[3]), glue = { encoder_filter = "IncrementOnly" }, target = action(1012) }
add { id = "shift-enc3-out", name = "Shift + encoder 3 = zoom out (1011)", feedback_enabled = false, activation_condition = SHIFT_DOWN,
      source = encoder(ENC[3]), glue = { encoder_filter = "DecrementOnly" }, target = action(1011) }
-- encoder LEDs: 1 volume (green), 2 pan (azure), 3 browse (white), 4 tempo (orange); shift: 1 red (master)
paint(ENC[1], RGB.green, SHIFT_UP); paint(ENC[2], RGB.azure, SHIFT_UP); paint(ENC[3], RGB.white, SHIFT_UP); paint(ENC[4], RGB.orange, SHIFT_UP)
paint(ENC[1], RGB.red, SHIFT_DOWN); paint(ENC[2], RGB.yellow, SHIFT_DOWN); paint(ENC[3], RGB.cyan, SHIFT_DOWN); paint(ENC[4], dim(RGB.orange), SHIFT_DOWN)

-- encoder pushes: selected-track mute / solo / arm with state LEDs; push 4 = tap tempo through the Oxygen watcher
local pushes = {
    { ENC_PUSH[1], "mute", { kind = "TrackMuteState", track = SELECTED }, RGB.red },
    { ENC_PUSH[2], "solo", { kind = "TrackSoloState", track = SELECTED }, RGB.yellow },
    { ENC_PUSH[3], "arm",  { kind = "TrackArmState",  track = SELECTED }, RGB.red },
}
for _, p in ipairs(pushes) do
    add { id = "push-" .. p[2], name = "Encoder push: selected track " .. p[2], feedback_enabled = false,
          source = cc_button(CH, p[1]), glue = TOGGLE, target = p[3] }
    led(p[1], p[3], p[4], dim(p[4]))
end
add { id = "push-tap", name = "Encoder 4 push = tap tempo (Oxygen watcher)", feedback_enabled = false,
      source = cc_button(CH, ENC_PUSH[4]), glue = PRESS,
      target = { kind = "SendMidi", message = "B0 66 7F", destination = { kind = "InputDevice", device_id = PORT1_INPUT_DEVICE } } }
paint(ENC_PUSH[4], RGB.white)

-- ---- slider: six zones = go to marker 1-6 --------------------------------------------------------------
-- measured 2026-09-04 (fw 3.0.0): each slider zone reports as its own button, CC 80-85 on channel 16 (127 touch / 0 release),
-- not as CC 90 with a zone number as the spec says
for k = 0, 5 do
    add { id = "slider-" .. (k + 1), name = "Slider zone " .. (k + 1) .. " = go to marker " .. (k + 1), feedback_enabled = false,
          source = cc_button(CH, SLIDER_LED[k + 1]), glue = PRESS, target = action(40161 + k) }
    paint(SLIDER_LED[k + 1], RGB.orange)
end

return { parameters = parameters, mappings = mappings }

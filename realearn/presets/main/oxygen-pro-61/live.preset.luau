--- name: Oxygen Pro 61 - Live mode (port 3, single unit)
--- realearn_version: 2.18.0
--- author: James Alexander (built with Claude, 2026-09-03)
--- description: |
---     One ReaLearn unit for the M-Audio Oxygen Pro 61 running in its Ableton "Live" firmware mode
---     (sysex F0 00 01 05 7F 00 00 6D 00 01 02 F7, sent by "Oxygen Pro - Live watcher.lua" with the LED unlock).
---     Every gesture arrives on USB port 3: Mode buttons (CC 57-61 ch 16), bank buttons (CC 110/111),
---     knob-function buttons (CC 83/85/86/87 ch 16), faders (CC 12-19, master 41), knobs (CC 22-29),
---     fader buttons (CC 32-39, latching), pads (notes 36-51), pad side buttons (CC 107/108),
---     transport (CC 114-119), encoder (CC 103 relative, press 102), DAW button (CC 113).
---     Input "MIDIIN3 (Oxygen Pro 61)" (control-only in REAPER), output "MIDIOUT3 (Oxygen Pro 61)".
---
---     Fader banks (Bank < / >): 1 tracks 1-8 · 2 selected track + focused FX · 3 tracks 9-16 · 4 free.
---     Knob function (Shift + pad 9 / 10 / 11, and CC 83 if a button sends it):
---       Pan · Device (focused FX params 1-8) · Send 1 of each track · Sends 1-8 of the selected track.
---     LAYOUTS (DAW button toggles): "General DAW" and "LoopCanvas". They differ only in pad modes.
---       Pad modes (side buttons beside the pads step through them; colours identify them):
---       General:    Drums · Mixer 1-8 · Mixer 9-16 · Markers & utilities · Free
---       LoopCanvas: Drums · LoopCanvas press/drop · LoopCanvas return/align · Mixer 1-8 · Free
---     Drums re-emit each hit into the "Oxygen Pro 61" (port 1) input as channel-10 notes 36-51.
--- setup_instructions: |
---     Run "Scripts/Oxygen Pro/Oxygen Pro - First time setup.lua" on a new machine; it fixes the device numbers below.

--!strict

local mappings = {}
local function add(m) table.insert(mappings, m) end

-- REAPER MIDI input device index of "Oxygen Pro 61" (port 1) on THIS machine; rewritten by the setup script
local PORT1_INPUT_DEVICE = 14

-- ---- parameters (all discrete) --------------------------------------------------
local P_BANK, P_MODE, P_KNOB, P_PAD = 0, 1, 2, 3
local P_VEL0 = 4                      -- parameters 4..19 hold the last hit velocity of pads 1..16
local P_LAYOUT = 20
local parameters = {
    { index = P_BANK, id = "bank", name = "Fader bank", value_count = 4,
      value_labels = { "Bank 1: tracks 1-8", "Bank 2: selected track / FX", "Bank 3: tracks 9-16", "Bank 4: free" } },
    { index = P_MODE, id = "mode", name = "Fader-button mode", value_count = 5,
      value_labels = { "Off", "Record", "Select", "Mute", "Solo" } },
    { index = P_KNOB, id = "knob", name = "Knob function", value_count = 4,
      value_labels = { "Pan", "Device (focused FX)", "Send 1 per track", "Selected track sends 1-8" } },
    { index = P_PAD, id = "padmode", name = "Pad mode", value_count = 5,
      value_labels = { "Drums", "Pad mode 2", "Pad mode 3", "Pad mode 4", "Free" } },
    { index = P_LAYOUT, id = "layout", name = "Layout", value_count = 2,
      value_labels = { "General DAW", "LoopCanvas" } },
    { index = 21, id = "back", name = "Back held (REAPER modifier)", value_count = 2, value_labels = { "up", "down" } },
}
local P_BACK = 21
for k = 1, 16 do
    table.insert(parameters, { index = P_VEL0 + k - 1, id = "vel" .. k, name = "Pad " .. k .. " velocity" })
end
local MODE_OFF, MODE_REC, MODE_SEL, MODE_MUTE, MODE_SOLO = 0, 1, 2, 3, 4
local KNOB_PAN, KNOB_DEV, KNOB_SEND, KNOB_SELSEND = 0, 1, 2, 3
local LAY_GENERAL, LAY_LOOP = 0, 1

local groups = {
    { id = "global", name = "Global" },
    { id = "bank1", name = "Bank 1: tracks 1-8",          activation_condition = { kind = "Bank", parameter = P_BANK, bank_index = 0 } },
    { id = "bank2", name = "Bank 2: selected track / FX", activation_condition = { kind = "Bank", parameter = P_BANK, bank_index = 1 } },
    { id = "bank3", name = "Bank 3: tracks 9-16",         activation_condition = { kind = "Bank", parameter = P_BANK, bank_index = 2 } },
    { id = "bank4", name = "Bank 4: free",                activation_condition = { kind = "Bank", parameter = P_BANK, bank_index = 3 } },
    { id = "drums", name = "Pads: drums (both layouts)",  activation_condition = { kind = "Bank", parameter = P_PAD, bank_index = 0 } },
    { id = "lay0",  name = "Layout: General DAW pads",    activation_condition = { kind = "Bank", parameter = P_LAYOUT, bank_index = LAY_GENERAL } },
    { id = "lay1",  name = "Layout: LoopCanvas pads",     activation_condition = { kind = "Bank", parameter = P_LAYOUT, bank_index = LAY_LOOP } },
}

-- ---- helpers ----------------------------------------------------------------------
local function cc_button(ch, n)   return { kind = "MidiControlChangeValue", channel = ch, controller_number = n, character = "Button" } end
local function cc_range(ch, n)    return { kind = "MidiControlChangeValue", channel = ch, controller_number = n, character = "Range" } end
-- fader buttons alternate 127 / 0 on successive presses: "Toggle-only button" counts every message as a press
local function cc_latching(ch, n) return { kind = "MidiControlChangeValue", channel = ch, controller_number = n, character = "StatefulButton" } end
local function note(n)            return { kind = "MidiNoteVelocity", channel = 0, key_number = n } end
local function param(i)           return { kind = "CompartmentParameterValue", parameter = { address = "ById", index = i } } end
local function cond(p, v)         return { kind = "Bank", parameter = p, bank_index = v } end
local function track(i)           return { address = "ByIndex", index = i } end
local MASTER   = { address = "Master" }
local SELECTED = { address = "Selected" }
local PICKUP   = { takeover_mode = "PickUp" }
local TOGGLE   = { absolute_mode = "ToggleButton" }
local PRESS    = { button_filter = "PressOnly" }

-- LED address of pad k (1-16, left to right, top row then bottom row) = the note it sends
local PAD_NOTE = { 40, 41, 42, 43, 48, 49, 50, 51, 36, 37, 38, 39, 44, 45, 46, 47 }
local C = { off = 0, red = 3, orange = 11, green = 12, chartreuse = 14, yellow = 15, rose = 35,
            aqua = 44, blue = 48, violet = 50, magenta = 51, azure = 56, cyan = 60, white = 63 }

local function state_target(mode, trk)
    if mode == MODE_REC  then return { kind = "TrackArmState", track = trk } end
    if mode == MODE_SEL  then return { kind = "TrackSelectionState", track = trk, scroll_arrange_view = true, scroll_mixer = true } end
    if mode == MODE_MUTE then return { kind = "TrackMuteState", track = trk } end
    if mode == MODE_SOLO then return { kind = "TrackSoloState", track = trk } end
    return nil
end

-- fader button i (0-7) in a bank: control + LED for every Mode, dark in Off mode
local function fader_button_row(group, targets_by_mode)
    for i = 0, 7 do
        for mode = MODE_OFF, MODE_SOLO do
            local tgt = targets_by_mode(mode, i)
            if tgt ~= nil then
                add { id = string.format("%s-btn-m%d-%d", group, mode, i + 1), name = string.format("%s btn%d mode%d", group, i + 1, mode),
                      group = group, feedback_enabled = false, activation_condition = cond(P_MODE, mode),
                      source = cc_latching(0, 32 + i), glue = TOGGLE, target = tgt }
                add { id = string.format("%s-led-m%d-%d", group, mode, i + 1), name = string.format("%s LED%d mode%d", group, i + 1, mode),
                      group = group, control_enabled = false, activation_condition = cond(P_MODE, mode),
                      source = cc_button(0, 32 + i), target = tgt }
            else
                add { id = string.format("%s-led-m%d-dark-%d", group, mode, i + 1), name = "LED off",
                      group = group, control_enabled = false, activation_condition = cond(P_MODE, mode),
                      source = cc_button(0, 32 + i), target = { kind = "Dummy" } }
            end
        end
    end
end

-- pad helpers. `padmode` gates the mapping inside its layout group (nil = no extra gate).
local function colour_script(n, expr)
    return "local c = " .. expr .. "\nreturn { address = " .. n .. ", messages = { { 0x90, " .. n .. ", c } } }"
end
-- fixed colour, painted whenever the mapping becomes active
local function paint(group, padmode, k, colour)
    local n = PAD_NOTE[k]
    add { id = string.format("%s-p%d-paint-%d", group, padmode or 0, k), name = string.format("Paint pad %d", k),
          group = group, control_enabled = false, activation_condition = padmode and cond(P_PAD, padmode) or nil,
          source = { kind = "MidiScript", script_kind = "Lua", script = colour_script(n, tostring(colour)) },
          target = { kind = "Dummy" } }
end
-- pad toggles an on/off target and shows it
local function state_pad(group, padmode, k, tgt, on_colour, off_colour)
    local n = PAD_NOTE[k]
    add { id = string.format("%s-p%d-pad-%d", group, padmode, k), name = string.format("pad %d toggle", k),
          group = group, feedback_enabled = false, activation_condition = cond(P_PAD, padmode),
          source = note(n), glue = TOGGLE, target = tgt }
    add { id = string.format("%s-p%d-padled-%d", group, padmode, k), name = string.format("pad %d colour", k),
          group = group, control_enabled = false, activation_condition = cond(P_PAD, padmode),
          source = { kind = "MidiScript", script_kind = "Lua",
                     script = colour_script(n, off_colour .. "\nif y ~= nil and y > 0 then c = " .. on_colour .. " end") },
          target = tgt }
end
-- pad fires a REAPER action (trigger); optional state colours if the action reports on/off
local function action_pad(group, padmode, k, command, colour, on_colour)
    local n = PAD_NOTE[k]
    add { id = string.format("%s-p%d-pad-%d", group, padmode, k), name = tostring(command),
          group = group, feedback_enabled = false, activation_condition = cond(P_PAD, padmode),
          source = note(n), glue = PRESS, target = { kind = "ReaperAction", command = command, invocation = "Trigger" } }
    if on_colour then
        add { id = string.format("%s-p%d-padled-%d", group, padmode, k), name = string.format("pad %d state", k),
              group = group, control_enabled = false, activation_condition = cond(P_PAD, padmode),
              source = { kind = "MidiScript", script_kind = "Lua",
                         script = colour_script(n, colour .. "\nif y ~= nil and y > 0 then c = " .. on_colour .. " end") },
              target = { kind = "ReaperAction", command = command, invocation = "Trigger" } }
    else
        paint(group, padmode, k, colour)
    end
end

local function focused_fx_param(index)
    return { kind = "FxParameterValue", parameter = { address = "ByIndex", fx = { address = "Focused" }, index = index } }
end

-- ---- global: mode / knob-function / bank / pad-mode / layout tracking, transport, encoder, master ----
-- Back button (CC 104, 127 while held, 0 on release) is REAPER's own modifier: the firmware's Shift button
-- swallows Play / Record / Loop / pads / fader buttons (measured 2026-09-03: no CC leaves the keyboard while
-- Shift is held, and after Shift + fader button the Shift release itself is not sent), so Shift is unusable
-- as a host modifier. Back is a plain momentary button that the firmware never combines with anything.
-- Measured 2026-09-03: while ANY button is held the keyboard sends nothing for a second button (Back + <<,
-- Back + Bank, Back + Play all silent), so Back cannot be a hold-modifier either. It is a one-shot LATCH
-- instead: press Back (arms the Back layer, pads sweep violet via the watcher), then press the button whose
-- alternate function you want; that press fires the function and drops the layer. Back again = cancel.
add { id = "back-state", name = "Back layer (latch)", group = "global", feedback_enabled = false,
      source = cc_button(0, 104), glue = { absolute_mode = "ToggleButton" }, target = param(P_BACK) }
local BACK_UP   = { kind = "Modifier", modifiers = { { parameter = P_BACK, on = false } } }
local BACK_DOWN = { kind = "Modifier", modifiers = { { parameter = P_BACK, on = true } } }
-- tell the Live watcher (port 1) when the layer arms (7F) or is cancelled / consumed (00)
local BACK_ECHO_ON  = { kind = "SendMidi", message = "B0 68 7F", destination = { kind = "InputDevice", device_id = PORT1_INPUT_DEVICE } }
local BACK_ECHO_OFF = { kind = "SendMidi", message = "B0 68 00", destination = { kind = "InputDevice", device_id = PORT1_INPUT_DEVICE } }
add { id = "back-arm-echo", name = "Back armed -> watcher", group = "global", feedback_enabled = false, activation_condition = BACK_UP,
      source = cc_button(0, 104), glue = PRESS, target = BACK_ECHO_ON }
add { id = "back-cancel-echo", name = "Back cancelled -> watcher", group = "global", feedback_enabled = false, activation_condition = BACK_DOWN,
      source = cc_button(0, 104), glue = PRESS, target = BACK_ECHO_OFF }
-- any button that has a Back function drops the layer after firing it (and tells the watcher)
for _, cc in ipairs({ 115, 116, 110, 111, 118, 119, 114, 117, 102 }) do
    add { id = "back-drop-" .. cc, name = "Back layer consumed (CC " .. cc .. ")", group = "global", feedback_enabled = false,
          activation_condition = BACK_DOWN, source = cc_button(0, cc),
          glue = { button_filter = "PressOnly", target_interval = { 0, 0 } }, target = param(P_BACK) }
    add { id = "back-drop-echo-" .. cc, name = "Back layer consumed -> watcher", group = "global", feedback_enabled = false,
          activation_condition = BACK_DOWN, source = cc_button(0, cc), glue = PRESS, target = BACK_ECHO_OFF }
end
for cc, idx in pairs({ [57] = MODE_OFF, [58] = MODE_REC, [59] = MODE_SEL, [60] = MODE_MUTE, [61] = MODE_SOLO }) do
    add { id = "mode-" .. cc, name = "Mode button", group = "global", feedback_enabled = false,
          source = cc_button(15, cc), glue = { button_filter = "PressOnly", target_interval = { idx / 4, idx / 4 } }, target = param(P_MODE) }
end
for cc, idx in pairs({ [85] = KNOB_PAN, [86] = KNOB_DEV, [87] = KNOB_SEND, [83] = KNOB_SELSEND }) do
    add { id = "knobmode-" .. cc, name = "Knob function button", group = "global", feedback_enabled = false,
          source = cc_button(15, cc), glue = { button_filter = "PressOnly", target_interval = { idx / 3, idx / 3 } }, target = param(P_KNOB) }
end
add { id = "bank-left", name = "Bank <", group = "global", feedback_enabled = false, activation_condition = BACK_UP, source = cc_button(0, 110),
      glue = { absolute_mode = "IncrementalButton", reverse = true, step_factor_interval = { 1, 1 } }, target = param(P_BANK) }
add { id = "bank-right", name = "Bank >", group = "global", feedback_enabled = false, activation_condition = BACK_UP, source = cc_button(0, 111),
      glue = { absolute_mode = "IncrementalButton", step_factor_interval = { 1, 1 } }, target = param(P_BANK) }
-- ... and echo each bank press into the port-1 input so the Live watcher can flash the pad of the new bank number
for cc, msg in pairs({ [110] = "B0 6E 7F", [111] = "B0 6F 7F" }) do
    add { id = "bank-echo-" .. cc, name = "Bank press -> watcher", group = "global", feedback_enabled = false, activation_condition = BACK_UP,
          source = cc_button(0, cc), glue = PRESS,
          target = { kind = "SendMidi", message = msg, destination = { kind = "InputDevice", device_id = PORT1_INPUT_DEVICE } } }
end
add { id = "padmode-prev", name = "Pad mode < (top side button)", group = "global", feedback_enabled = false, source = cc_button(0, 107),
      glue = { absolute_mode = "IncrementalButton", reverse = true, wrap = true, step_factor_interval = { 1, 1 } }, target = param(P_PAD) }
add { id = "padmode-next", name = "Pad mode > (bottom side button)", group = "global", feedback_enabled = false, source = cc_button(0, 108),
      glue = { absolute_mode = "IncrementalButton", wrap = true, step_factor_interval = { 1, 1 } }, target = param(P_PAD) }
-- the DAW button toggles the layout (in Live mode it only sends CC 113)
add { id = "layout-toggle", name = "Layout toggle (DAW button)", group = "global", feedback_enabled = false, source = cc_button(0, 113),
      glue = { absolute_mode = "IncrementalButton", wrap = true, step_factor_interval = { 1, 1 } }, target = param(P_LAYOUT) }
-- ... and a copy of the press is injected into the port-1 input so the Live watcher (which cannot see the
-- control-only port 3 in REAPER's recent-input buffer) can flash the layout colour across the pads
add { id = "layout-echo", name = "Layout press -> watcher", group = "global", feedback_enabled = false, source = cc_button(0, 113),
      glue = PRESS, target = { kind = "SendMidi", message = "B0 71 7F", destination = { kind = "InputDevice", device_id = PORT1_INPUT_DEVICE } } }

-- transport with Back up
add { id = "stop", name = "Stop", group = "global", feedback_enabled = false, activation_condition = BACK_UP,
      source = cc_button(0, 117), glue = PRESS, target = { kind = "TransportAction", action = "Stop" } }
add { id = "loop", name = "Repeat", group = "global", feedback_enabled = false, activation_condition = BACK_UP,
      source = cc_button(0, 114), glue = TOGGLE, target = { kind = "TransportAction", action = "Repeat" } }
add { id = "play", name = "Play/Stop", group = "global", feedback_enabled = false, activation_condition = BACK_UP,
      source = cc_button(0, 118), glue = TOGGLE, target = { kind = "TransportAction", action = "PlayStop" } }
add { id = "record", name = "Record", group = "global", feedback_enabled = false, activation_condition = BACK_UP,
      source = cc_button(0, 119), glue = TOGGLE, target = { kind = "TransportAction", action = "Record" } }
-- << and >>: go to start / end. (Shift + << / >> is a firmware function: it types zoom keystrokes and sends no CC.)
add { id = "rewind", name = "Go to start (40042)", group = "global", feedback_enabled = false, activation_condition = BACK_UP,
      source = cc_button(0, 115), glue = PRESS, target = { kind = "ReaperAction", command = 40042, invocation = "Trigger" } }
add { id = "ffwd", name = "Go to end (40043)", group = "global", feedback_enabled = false, activation_condition = BACK_UP,
      source = cc_button(0, 116), glue = PRESS, target = { kind = "ReaperAction", command = 40043, invocation = "Trigger" } }
-- Back layer armed: << / >> = undo / redo, Bank < / > = previous / next marker, Play = insert marker,
--            Record = metronome on/off, Loop = toggle mixer,
--            Stop = save project (General DAW) / cancel pending section change (LoopCanvas),
--            encoder turn = zoom out / in, encoder press = insert new track
local function back_combo(id, name, cc, group, command)
    add { id = id, name = "Back + " .. name, group = group, feedback_enabled = false, activation_condition = BACK_DOWN,
          source = cc_button(0, cc), glue = PRESS, target = { kind = "ReaperAction", command = command, invocation = "Trigger" } }
end
back_combo("back-rewind", "<< = Undo (40029)",              115, "global", 40029)
back_combo("back-ffwd",   ">> = Redo (40030)",              116, "global", 40030)
back_combo("back-bank-left",  "Bank < = Previous marker (40172)", 110, "global", 40172)
back_combo("back-bank-right", "Bank > = Next marker (40173)",     111, "global", 40173)
back_combo("back-play",   "Play = Insert marker (40157)",   118, "global", 40157)
back_combo("back-record", "Record = Metronome on/off (40364)", 119, "global", 40364)
back_combo("back-loop",   "Loop = Toggle mixer (40078)",    114, "global", 40078)
back_combo("back-stop-general", "Stop = Save project (40026)", 117, "lay0", 40026)
back_combo("back-stop-loop", "Stop = LoopCanvas section cancel", 117, "lay1", "_LOOPCANVAS_SECTION_CANCEL")
back_combo("back-encoder-press", "encoder press = Insert new track (40001)", 102, "global", 40001)
-- Back + encoder turn: zoom the arrange view (clockwise = zoom in 1012, anticlockwise = zoom out 1011)
for _, z in ipairs({ { "in", "IncrementOnly", 1012 }, { "out", "DecrementOnly", 1011 } }) do
    add { id = "back-encoder-zoom-" .. z[1], name = "Back + encoder = zoom " .. z[1] .. " (" .. z[3] .. ")", group = "global",
          feedback_enabled = false, activation_condition = BACK_DOWN,
          source = { kind = "MidiControlChangeValue", channel = 0, controller_number = 103, character = "Relative2" },
          glue = { encoder_filter = z[2] },
          target = { kind = "ReaperAction", command = z[3], invocation = "Trigger" } }
end
add { id = "encoder", name = "Browse tracks", group = "global", feedback_enabled = false, activation_condition = BACK_UP,
      source = { kind = "MidiControlChangeValue", channel = 0, controller_number = 103, character = "Relative2" },
      target = { kind = "BrowseTracks", scroll_arrange_view = true, scroll_mixer = true } }
-- encoder press = tap tempo: each press is echoed into the port-1 input, where the Live watcher averages
-- the taps and sets REAPER's project tempo (the keyboard's own Tempo button sends nothing)
add { id = "tap-tempo-echo", name = "Encoder press -> tap tempo (watcher)", group = "global", feedback_enabled = false, activation_condition = BACK_UP,
      source = cc_button(0, 102), glue = PRESS,
      target = { kind = "SendMidi", message = "B0 66 7F", destination = { kind = "InputDevice", device_id = PORT1_INPUT_DEVICE } } }
-- (The metronome is on Shift+Tempo via a REAPER keyboard shortcut, and on the Markers pad mode.)
add { id = "master", name = "Master volume", group = "global", feedback_enabled = false, source = cc_range(0, 41), glue = PICKUP,
      target = { kind = "TrackVolume", track = MASTER } }

-- ---- fader banks ---------------------------------------------------------------------------
local function mixer_bank(group, first_track)
    for i = 0, 7 do
        local t = track(first_track + i)
        add { id = string.format("%s-fader-%d", group, i + 1), name = string.format("Tr%d volume", first_track + i + 1),
              group = group, feedback_enabled = false, source = cc_range(0, 12 + i), glue = PICKUP,
              target = { kind = "TrackVolume", track = t } }
        local knob_targets = {
            [KNOB_PAN]     = { kind = "TrackPan", track = t },
            [KNOB_DEV]     = focused_fx_param(i),
            [KNOB_SEND]    = { kind = "RouteVolume", route = { address = "ByIndex", track = t, route_kind = "Send", index = 0 } },
            [KNOB_SELSEND] = { kind = "RouteVolume", route = { address = "ByIndex", track = SELECTED, route_kind = "Send", index = i } },
        }
        for km, tgt in pairs(knob_targets) do
            add { id = string.format("%s-knob-k%d-%d", group, km, i + 1), name = string.format("knob %d function %d", i + 1, km),
                  group = group, feedback_enabled = false, activation_condition = cond(P_KNOB, km),
                  source = cc_range(0, 22 + i), glue = PICKUP, target = tgt }
        end
    end
    fader_button_row(group, function(mode, i) return state_target(mode, track(first_track + i)) end)
end
mixer_bank("bank1", 0)
mixer_bank("bank3", 8)

-- bank 2: selected track + focused FX
for i = 0, 7 do
    add { id = string.format("bank2-fader-%d", i + 1), name = string.format("Focused FX param %d", i + 1),
          group = "bank2", feedback_enabled = false, source = cc_range(0, 12 + i), glue = PICKUP, target = focused_fx_param(i) }
    add { id = string.format("bank2-knob-%d", i + 1), name = string.format("Focused FX param %d", i + 9),
          group = "bank2", feedback_enabled = false, source = cc_range(0, 22 + i), glue = PICKUP, target = focused_fx_param(8 + i) }
end
local sel_mute_row = {
    { kind = "TrackMuteState", track = SELECTED },
    { kind = "TrackSoloState", track = SELECTED },
    { kind = "TrackArmState", track = SELECTED },
    { kind = "AllTrackFxOnOffState", track = SELECTED },
}
fader_button_row("bank2", function(mode, i)
    if mode == MODE_SEL then
        return { kind = "FxOnOffState", fx = { address = "ByIndex", chain = { address = "Track", track = SELECTED }, index = i } }
    elseif mode == MODE_MUTE then
        return sel_mute_row[i + 1]
    end
    return nil
end)

-- bank 4: free (LEDs dark)
fader_button_row("bank4", function(mode, i) return nil end)

-- ---- pad mode 0 in both layouts: drums ------------------------------------------------------
for k = 1, 16 do
    local n = PAD_NOTE[k]
    add { id = string.format("drums-inject-%d", k), name = string.format("Pad %d -> port 1 ch10 note %d", k, n),
          group = "drums", feedback_enabled = false, source = note(n),
          target = { kind = "SendMidi", message = string.format("99 %02X [0gfe dcba]", n),
                     destination = { kind = "InputDevice", device_id = PORT1_INPUT_DEVICE } } }
    add { id = string.format("drums-vel-%d", k), name = string.format("Pad %d velocity", k),
          group = "drums", feedback_enabled = false, source = note(n), target = param(P_VEL0 + k - 1) }
    add { id = string.format("drums-led-%d", k), name = string.format("Pad %d colour", k),
          group = "drums", control_enabled = false,
          source = { kind = "MidiScript", script_kind = "Lua",
                     script = colour_script(n, C.blue .. "\nif y ~= nil and y > 0 then\n  if y < 0.34 then c = " .. C.green
                         .. "\n  elseif y < 0.67 then c = " .. C.yellow .. "\n  else c = " .. C.red .. " end\nend") },
          target = param(P_VEL0 + k - 1) }
end

-- ---- mixer grids (used by both layouts) -------------------------------------------------------
local function mixer_grid(group, padmode, first_track)
    for k = 1, 8 do
        state_pad(group, padmode, k,     { kind = "TrackMuteState", track = track(first_track + k - 1) }, C.red, C.chartreuse)
        state_pad(group, padmode, k + 8, { kind = "TrackSoloState", track = track(first_track + k - 1) }, C.yellow, C.azure)
    end
end

-- ---- layout 0: General DAW -----------------------------------------------------------------------
mixer_grid("lay0", 1, 0)
mixer_grid("lay0", 2, 8)
-- pad mode 3: markers and utilities  (verify the numeric action IDs in the Actions window)
for k = 1, 8 do action_pad("lay0", 3, k, 40160 + k, C.orange) end          -- Markers: go to marker 1-8
action_pad("lay0", 3, 9,  40157, C.white)                                    -- insert marker at current position
action_pad("lay0", 3, 10, 40172, C.azure)                                    -- go to previous marker
action_pad("lay0", 3, 11, 40173, C.azure)                                    -- go to next marker
add { id = "lay0-p3-pad-12", name = "Repeat toggle", group = "lay0", feedback_enabled = false, activation_condition = cond(P_PAD, 3),
      source = note(PAD_NOTE[12]), glue = TOGGLE, target = { kind = "TransportAction", action = "Repeat" } }
add { id = "lay0-p3-padled-12", name = "Repeat state", group = "lay0", control_enabled = false, activation_condition = cond(P_PAD, 3),
      source = { kind = "MidiScript", script_kind = "Lua", script = colour_script(PAD_NOTE[12], C.azure .. "\nif y ~= nil and y > 0 then c = " .. C.yellow .. " end") },
      target = { kind = "TransportAction", action = "Repeat" } }
action_pad("lay0", 3, 13, 40029, C.violet)                                   -- undo
action_pad("lay0", 3, 14, 40030, C.violet)                                   -- redo
action_pad("lay0", 3, 15, 40026, C.green)                                    -- save project
action_pad("lay0", 3, 16, 40364, C.off, C.magenta)                           -- metronome on/off (reports state)
for k = 1, 16 do paint("lay0", 4, k, C.white) end

-- ---- layout 1: LoopCanvas ---------------------------------------------------------------------------
for k = 1, 16 do
    if k <= 8 then action_pad("lay1", 1, k, "_LOOPCANVAS_PRESS_SLOT_" .. k, C.green)
    else action_pad("lay1", 1, k, "_LOOPCANVAS_DROP_SLOT_" .. (k - 8), C.azure) end
end
for k = 1, 16 do
    if k <= 8 then action_pad("lay1", 2, k, "_LOOPCANVAS_RETURN_SECTION_" .. k, C.yellow)
    else action_pad("lay1", 2, k, "_LOOPCANVAS_ALIGN_SLOT_" .. (k - 8), C.violet) end
end
mixer_grid("lay1", 3, 0)
for k = 1, 16 do paint("lay1", 4, k, C.white) end

return { parameters = parameters, groups = groups, mappings = mappings }

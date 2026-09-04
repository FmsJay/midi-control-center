-- ==== Exquis preset interpreter (appended after `local MODEL = { ... }`, MODEL = model.exquis) ================
-- Builds the ReaLearn unit for the Intuitive Instruments Exquis in Developer Mode (zone mask 2E: encoders, slider,
-- Up/Down and the six action buttons; pads stay native MPE). Taken-over controls report on channel 16.
-- LEDs: sysex F0 00 21 7E 7F 04 <id> r g b fx F7. Runs in ReaLearn's Luau sandbox (no table.concat, no require).

local mappings = {}
local function add(m) table.insert(mappings, m) end

local CH = 15
local SHIFT_CC, SHIFT_CH = MODEL.shift_cc or 105, MODEL.shift_channel or 13
local PORT1_INPUT_DEVICE = MODEL.port1_input_device or 14

local BTN = { record = 102, loop = 103, clips = 104, play = 105, down = 106, up = 107, undo = 108, redo = 109 }
local BTN_ORDER = { "play", "record", "loop", "clips", "undo", "redo", "down", "up" }
local ENC = { 110, 111, 112, 113 }
local ENC_PUSH = { 114, 115, 116, 117 }
local SLIDER_LED = { 80, 81, 82, 83, 84, 85 }

local P_SHIFT = 0
local parameters = {
    { index = P_SHIFT, id = "shift", name = "Shift (FCB1010 hold)", value_count = 2, value_labels = { "up", "held" } },
}
local SHIFT_UP   = { kind = "Modifier", modifiers = { { parameter = P_SHIFT, on = false } } }
local SHIFT_DOWN = { kind = "Modifier", modifiers = { { parameter = P_SHIFT, on = true } } }

local function cc_button(ch, n) return { kind = "MidiControlChangeValue", channel = ch, controller_number = n, character = "Button" } end
local function encoder(n)       return { kind = "MidiControlChangeValue", channel = CH, controller_number = n, character = "Relative2" } end
local function action(cmd)      return { kind = "ReaperAction", command = cmd, invocation = "Trigger" } end
local function param(i)         return { kind = "CompartmentParameterValue", parameter = { address = "ById", index = i } } end
local SELECTED = { address = "Selected" }
local MASTER   = { address = "Master" }
local PRESS    = { button_filter = "PressOnly" }
local TOGGLE   = { absolute_mode = "ToggleButton" }

local RGB = {
    green = { 0, 127, 0 }, red = { 127, 0, 0 }, yellow = { 127, 90, 0 }, violet = { 70, 0, 127 }, azure = { 0, 70, 127 },
    white = { 90, 90, 90 }, orange = { 127, 40, 0 }, cyan = { 0, 110, 110 }, magenta = { 127, 0, 100 }, off = { 0, 0, 0 },
}
local function dim(c) return { math.floor(c[1] / 6), math.floor(c[2] / 6), math.floor(c[3] / 6) } end
local function colour(a, default)
    local c = RGB[(a and a.colour) or default or "off"] or RGB.off
    if a and a.dim then c = dim(c) end
    return c
end
local function rgb_list(c) return c[1] .. ", " .. c[2] .. ", " .. c[3] end
local function led_script(id, on, off)
    return "local r, g, b = " .. rgb_list(off) .. "\n"
        .. "if y ~= nil and y > 0 then r, g, b = " .. rgb_list(on) .. " end\n"
        .. "return { address = " .. id .. ", messages = { { 0xF0, 0x00, 0x21, 0x7E, 0x7F, 0x04, " .. id .. ", r, g, b, 0x00, 0xF7 } } }"
end
local function led(id, target, on, off, condition)
    add { id = "led-" .. id .. (condition == SHIFT_DOWN and "-shift" or ""), name = "LED " .. id, control_enabled = false,
          activation_condition = condition,
          source = { kind = "MidiScript", script_kind = "Lua", script = led_script(id, on, off or dim(on)) }, target = target }
end
local function paint(id, c, condition) led(id, { kind = "Dummy" }, c, c, condition) end

-- Developer Mode on load (feedback-only mapping fires once when the unit activates); hand back on unload
add { id = "devmode", name = "Exquis Developer Mode (encoders, slider, up/down, buttons)", control_enabled = false,
      source = { kind = "MidiScript", script_kind = "Lua",
                 script = "return { address = 0, messages = { { 0xF0, 0x00, 0x21, 0x7E, 0x7F, 0x00, 0x2E, 0xF7 } } }" },
      target = { kind = "Dummy" },
      on_deactivate = { send_midi_feedback = { { kind = "Raw", message = "F0 00 21 7E 7F 00 00 F7" } } } }

-- shift (external hold, injected by the FCB1010 bridge)
add { id = "shift", name = "Shift held (FCB1010 via bridge)", feedback_enabled = false,
      source = cc_button(SHIFT_CH, SHIFT_CC), target = param(P_SHIFT) }

-- ---- buttons: normal layer and shift layer -------------------------------------------------------
local function button_target(a)
    if a == nil or a.kind == "none" then return nil end
    if a.kind == "action" then return action(a.command), PRESS, false end
    if a.kind == "builtin" then
        if a.builtin == "transport_play"   then return { kind = "TransportAction", action = "PlayStop" }, TOGGLE, true end
        if a.builtin == "transport_record" then return { kind = "TransportAction", action = "Record" }, TOGGLE, true end
        if a.builtin == "transport_loop"   then return { kind = "TransportAction", action = "Repeat" }, TOGGLE, true end
        if a.builtin == "transport_stop"   then return { kind = "TransportAction", action = "Stop" }, PRESS, false end
        if a.builtin == "tap_tempo" then
            return { kind = "SendMidi", message = "B0 66 7F", destination = { kind = "InputDevice", device_id = PORT1_INPUT_DEVICE } }, PRESS, false
        end
    end
    return nil
end
local function emit_button(prefix, elem_id, a, condition)
    local tgt, glue, stateful = button_target(a)
    if not tgt then
        if a and a.colour then paint(elem_id, colour(a), condition) end
        return
    end
    add { id = prefix .. elem_id, name = (a.name or a.kind) .. " " .. elem_id, feedback_enabled = false, activation_condition = condition,
          source = cc_button(CH, elem_id), glue = glue, target = tgt }
    if stateful then led(elem_id, tgt, colour(a, "green"), nil, condition)
    elseif a.colour then paint(elem_id, colour(a), condition) end
end
for _, name in ipairs(BTN_ORDER) do
    emit_button("btn-", BTN[name], MODEL.buttons and MODEL.buttons[name], SHIFT_UP)
    emit_button("shift-btn-", BTN[name], MODEL.shift and MODEL.shift.buttons and MODEL.shift.buttons[name], SHIFT_DOWN)
end

-- ---- encoders -----------------------------------------------------------------------------------
local function emit_encoder(prefix, i, a, condition)
    local src = encoder(ENC[i])
    local k = a and a.kind or "none"
    local base = { feedback_enabled = false, activation_condition = condition }
    local function m(id, name, fields)
        local t = { id = prefix .. id, name = name }
        for kk, v in pairs(base) do t[kk] = v end
        for kk, v in pairs(fields) do t[kk] = v end
        add(t)
    end
    if k == "selected_volume" then m("enc" .. i, "Selected track volume", { source = src, target = { kind = "TrackVolume", track = SELECTED } })
    elseif k == "selected_pan" then m("enc" .. i, "Selected track pan", { source = src, target = { kind = "TrackPan", track = SELECTED } })
    elseif k == "master_volume" then m("enc" .. i, "Master volume", { source = src, target = { kind = "TrackVolume", track = MASTER } })
    elseif k == "selected_send" then
        m("enc" .. i, "Selected track send " .. ((a.index or 0) + 1), { source = src,
            target = { kind = "RouteVolume", route = { address = "ByIndex", track = SELECTED, route_kind = "Send", index = a.index or 0 } } })
    elseif k == "browse_tracks" then m("enc" .. i, "Browse tracks", { source = src, target = { kind = "BrowseTracks", scroll_arrange_view = true, scroll_mixer = true } })
    elseif k == "tempo" then m("enc" .. i, "Project tempo", { source = src, glue = { step_size_interval = { 0.001, 0.001 } }, target = { kind = "Tempo" } })
    elseif k == "fx_param" then
        m("enc" .. i, "Focused FX parameter " .. ((a.index or 0) + 1), { source = src,
            target = { kind = "FxParameterValue", parameter = { address = "ByIndex", fx = { address = "Focused" }, index = a.index or 0 } } })
    elseif k == "zoom" then
        m("enc" .. i .. "-in",  "Encoder " .. i .. " = zoom in (1012)",  { source = src, glue = { encoder_filter = "IncrementOnly" }, target = action(1012) })
        m("enc" .. i .. "-out", "Encoder " .. i .. " = zoom out (1011)", { source = src, glue = { encoder_filter = "DecrementOnly" }, target = action(1011) })
    elseif k == "actions" then
        m("enc" .. i .. "-cw",  "Encoder " .. i .. " clockwise " .. tostring(a.cw),      { source = src, glue = { encoder_filter = "IncrementOnly" }, target = action(a.cw) })
        m("enc" .. i .. "-ccw", "Encoder " .. i .. " anticlockwise " .. tostring(a.ccw), { source = src, glue = { encoder_filter = "DecrementOnly" }, target = action(a.ccw) })
    end
    if a and a.colour then paint(ENC[i], colour(a), condition) end
end
for i = 1, 4 do
    emit_encoder("", i, MODEL.encoders and MODEL.encoders[i], SHIFT_UP)
    emit_encoder("shift-", i, MODEL.shift and MODEL.shift.encoders and MODEL.shift.encoders[i], SHIFT_DOWN)
end

-- ---- encoder pushes (no shift layer) -----------------------------------------------------------------
local function emit_push(i, a)
    local elem = ENC_PUSH[i]
    local k = a and a.kind or "none"
    local state_targets = {
        selected_mute = { kind = "TrackMuteState", track = SELECTED },
        selected_solo = { kind = "TrackSoloState", track = SELECTED },
        selected_arm  = { kind = "TrackArmState",  track = SELECTED },
    }
    if state_targets[k] then
        add { id = "push-" .. i, name = "Encoder push " .. i .. ": " .. k, feedback_enabled = false,
              source = cc_button(CH, elem), glue = TOGGLE, target = state_targets[k] }
        local c = colour(a, "red")
        led(elem, state_targets[k], c, dim(c))
    elseif k == "tap_tempo" then
        add { id = "push-" .. i, name = "Encoder push " .. i .. " = tap tempo (Oxygen watcher)", feedback_enabled = false,
              source = cc_button(CH, elem), glue = PRESS,
              target = { kind = "SendMidi", message = "B0 66 7F", destination = { kind = "InputDevice", device_id = PORT1_INPUT_DEVICE } } }
        paint(elem, colour(a, "white"))
    elseif k == "action" then
        add { id = "push-" .. i, name = "Encoder push " .. i .. " = action " .. tostring(a.command), feedback_enabled = false,
              source = cc_button(CH, elem), glue = PRESS, target = action(a.command) }
        if a.colour then paint(elem, colour(a)) end
    elseif k == "transport" then
        local tgt = { kind = "TransportAction", action = a.action or "PlayStop" }
        add { id = "push-" .. i, name = "Encoder push " .. i .. " = " .. tostring(a.action), feedback_enabled = false,
              source = cc_button(CH, elem), glue = TOGGLE, target = tgt }
        led(elem, tgt, colour(a, "green"))
    elseif a and a.colour then
        paint(elem, colour(a))
    end
end
for i = 1, 4 do emit_push(i, MODEL.pushes and MODEL.pushes[i]) end

-- ---- slider zones (buttons on CC 80-85, measured) -------------------------------------------------------
for k = 1, 6 do
    local a = MODEL.slider and MODEL.slider[k]
    local elem = SLIDER_LED[k]
    if a and a.kind == "action" then
        add { id = "slider-" .. k, name = "Slider zone " .. k .. " = action " .. tostring(a.command), feedback_enabled = false,
              source = cc_button(CH, elem), glue = PRESS, target = action(a.command) }
        paint(elem, colour(a, "orange"))
    elseif a and a.kind == "transport" then
        local tgt = { kind = "TransportAction", action = a.action or "PlayStop" }
        add { id = "slider-" .. k, name = "Slider zone " .. k .. " = " .. tostring(a.action), feedback_enabled = false,
              source = cc_button(CH, elem), glue = TOGGLE, target = tgt }
        led(elem, tgt, colour(a, "green"))
    elseif a and a.colour then
        paint(elem, colour(a))
    end
end

return { parameters = parameters, mappings = mappings }

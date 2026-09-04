-- ==== Oxygen Pro 61 editor: preset interpreter ==================================================
-- This chunk is appended verbatim to a generated preset after `local MODEL = { ... }`. It turns the
-- model into ReaLearn parameters, groups and mappings. It runs inside ReaLearn's Luau sandbox, so it
-- uses only string.format, ipairs, pairs, table.insert and math (no table.concat, no require).

local mappings = {}
local function add(m) table.insert(mappings, m) end
local PORT1_INPUT_DEVICE = MODEL.port1_input_device

-- ---- catalogues -------------------------------------------------------------------------------
local PAD_NOTE = { 40, 41, 42, 43, 48, 49, 50, 51, 36, 37, 38, 39, 44, 45, 46, 47 }
local C = { off = 0, red = 3, orange = 11, green = 12, chartreuse = 14, yellow = 15, rose = 35,
            aqua = 44, blue = 48, violet = 50, magenta = 51, azure = 56, cyan = 60, white = 63 }
local function colour(name) return C[name or "off"] or 0 end
local CONTROL_CC = { play = 118, stop = 117, record = 119, loop = 114, rewind = 115, ffwd = 116, bank_prev = 110, bank_next = 111,
                     side_top = 107, side_bottom = 108, encoder_press = 102, back = 104, daw = 113 }
local CONTROL_ORDER = { "play", "stop", "record", "loop", "rewind", "ffwd", "bank_prev", "bank_next", "side_top", "side_bottom", "encoder_press", "back", "daw" }
local ENCODER_CC = 103

-- ---- parameters ---------------------------------------------------------------------------------
local P_BANK, P_MODE, P_KNOB, P_PAD = 0, 1, 2, 3
local P_VEL0 = 4
local P_LAYOUT = 20
local NEXT_PARAM = 21
local MODE_OFF, MODE_REC, MODE_SEL, MODE_MUTE, MODE_SOLO = 0, 1, 2, 3, 4
local KNOB_PAN, KNOB_DEV, KNOB_SEND, KNOB_SELSEND = 0, 1, 2, 3

local n_layouts = #MODEL.layouts
local n_modes = #MODEL.layouts[1].pad_modes
local n_banks = #MODEL.banks

local bank_labels, layout_labels, mode_labels = {}, {}, {}
for i, b in ipairs(MODEL.banks) do bank_labels[i] = b.name or ("Bank " .. i) end
for i, l in ipairs(MODEL.layouts) do layout_labels[i] = l.name or l.id end
for i = 1, n_modes do
    local name = MODEL.layouts[1].pad_modes[i].name or ("Pad mode " .. i)
    for li = 2, n_layouts do
        local other = MODEL.layouts[li].pad_modes[i].name
        if other and other ~= name then name = name .. " / " .. other end
    end
    mode_labels[i] = name
end

local parameters = {
    { index = P_BANK, id = "bank", name = "Fader bank", value_count = n_banks, value_labels = bank_labels },
    { index = P_MODE, id = "mode", name = "Fader-button mode", value_count = 5, value_labels = { "Off", "Record", "Select", "Mute", "Solo" } },
    { index = P_KNOB, id = "knob", name = "Knob function", value_count = 4,
      value_labels = { "Pan", "Device (focused FX)", "Send 1 per track", "Selected track sends 1-8" } },
    { index = P_PAD, id = "padmode", name = "Pad mode", value_count = n_modes, value_labels = mode_labels },
    { index = P_LAYOUT, id = "layout", name = "Layout", value_count = n_layouts, value_labels = layout_labels },
}
for k = 1, 16 do
    table.insert(parameters, { index = P_VEL0 + k - 1, id = "vel" .. k, name = "Pad " .. k .. " velocity" })
end

-- modifiers get one parameter each (21 upwards)
local MODIFIER_PARAM = {}
for _, cid in ipairs(CONTROL_ORDER) do
    local a = MODEL.buttons[cid]
    if a and a.kind == "modifier" then
        MODIFIER_PARAM[cid] = NEXT_PARAM
        table.insert(parameters, { index = NEXT_PARAM, id = "mod_" .. cid, name = "Modifier layer: " .. cid, value_count = 2, value_labels = { "off", "armed" } })
        NEXT_PARAM = NEXT_PARAM + 1
    end
end

-- external HOLD modifiers (another unit injects "CC on channel 14" into MIDIIN3: 127 held / 0 released)
local EXTERNAL_IDS = {}
for id, m in pairs(MODEL.modifiers or {}) do
    if type(m) == "table" and type(m.external) == "table" then table.insert(EXTERNAL_IDS, id) end
end
table.sort(EXTERNAL_IDS)
for _, id in ipairs(EXTERNAL_IDS) do
    MODIFIER_PARAM[id] = NEXT_PARAM
    table.insert(parameters, { index = NEXT_PARAM, id = "mod_" .. id, name = "Modifier (hold): " .. (MODEL.modifiers[id].external.name or id), value_count = 2, value_labels = { "up", "held" } })
    NEXT_PARAM = NEXT_PARAM + 1
end
local ALL_MODIFIER_IDS = {}
for _, cid in ipairs(CONTROL_ORDER) do if MODIFIER_PARAM[cid] then table.insert(ALL_MODIFIER_IDS, cid) end end
for _, id in ipairs(EXTERNAL_IDS) do table.insert(ALL_MODIFIER_IDS, id) end

-- Off mode: LEDs 1-4 mirror the keyboard's own ARP / Latch / Chord / Scale toggles. The firmware alternates the
-- button's CC value between 127 and 0 on successive presses, which is exactly its local on/off state.
local LOCAL_LED_PARAM = {}
if MODEL.off_mode_local_leds ~= false then
    local names = { "ARP", "Latch", "Chord", "Scale" }
    for i = 1, 4 do
        LOCAL_LED_PARAM[i] = NEXT_PARAM
        table.insert(parameters, { index = NEXT_PARAM, id = "local" .. i, name = "Keyboard " .. names[i] .. " (Off mode LED)", value_count = 2, value_labels = { "off", "on" } })
        NEXT_PARAM = NEXT_PARAM + 1
    end
end

-- ---- groups -----------------------------------------------------------------------------------
local groups = { { id = "global", name = "Global" } }
for i = 1, n_banks do
    table.insert(groups, { id = "bank" .. i, name = bank_labels[i], activation_condition = { kind = "Bank", parameter = P_BANK, bank_index = i - 1 } })
end
for li = 1, n_layouts do
    table.insert(groups, { id = "lay" .. (li - 1), name = "Layout: " .. layout_labels[li], activation_condition = { kind = "Bank", parameter = P_LAYOUT, bank_index = li - 1 } })
end

-- ---- helpers (identical to the hand-written preset) ---------------------------------------------
local function cc_button(ch, n)   return { kind = "MidiControlChangeValue", channel = ch, controller_number = n, character = "Button" } end
local function cc_range(ch, n)    return { kind = "MidiControlChangeValue", channel = ch, controller_number = n, character = "Range" } end
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
local function send_to_port1(msg)
    return { kind = "SendMidi", message = msg, destination = { kind = "InputDevice", device_id = PORT1_INPUT_DEVICE } }
end
local function reaper_action(command)
    return { kind = "ReaperAction", command = command, invocation = "Trigger" }
end

local function state_target(mode, trk)
    if mode == MODE_REC  then return { kind = "TrackArmState", track = trk } end
    if mode == MODE_SEL  then return { kind = "TrackSelectionState", track = trk, scroll_arrange_view = true, scroll_mixer = true } end
    if mode == MODE_MUTE then return { kind = "TrackMuteState", track = trk } end
    if mode == MODE_SOLO then return { kind = "TrackSoloState", track = trk } end
    return nil
end

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
            elseif mode == MODE_OFF and LOCAL_LED_PARAM[i + 1] then
                -- store the raw latching value (127 -> 1, 0 -> 0) and light the LED from it
                add { id = string.format("%s-local-m0-%d", group, i + 1), name = "Keyboard toggle state",
                      group = group, feedback_enabled = false, activation_condition = cond(P_MODE, mode),
                      source = cc_range(0, 32 + i), target = param(LOCAL_LED_PARAM[i + 1]) }
                add { id = string.format("%s-led-m0-local-%d", group, i + 1), name = "LED = keyboard toggle",
                      group = group, control_enabled = false, activation_condition = cond(P_MODE, mode),
                      source = cc_button(0, 32 + i), target = param(LOCAL_LED_PARAM[i + 1]) }
            else
                add { id = string.format("%s-led-m%d-dark-%d", group, mode, i + 1), name = "LED off",
                      group = group, control_enabled = false, activation_condition = cond(P_MODE, mode),
                      source = cc_button(0, 32 + i), target = { kind = "Dummy" } }
            end
        end
    end
end

local function colour_script(n, expr)
    return "local c = " .. expr .. "\nreturn { address = " .. n .. ", messages = { { 0x90, " .. n .. ", c } } }"
end
local function paint(group, padmode, k, col)
    local n = PAD_NOTE[k]
    add { id = string.format("%s-p%d-paint-%d", group, padmode or 0, k), name = string.format("Paint pad %d", k),
          group = group, control_enabled = false, activation_condition = padmode and cond(P_PAD, padmode) or nil,
          source = { kind = "MidiScript", script_kind = "Lua", script = colour_script(n, tostring(col)) },
          target = { kind = "Dummy" } }
end
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
local function action_pad(group, padmode, k, command, col, on_colour)
    local n = PAD_NOTE[k]
    add { id = string.format("%s-p%d-pad-%d", group, padmode, k), name = tostring(command),
          group = group, feedback_enabled = false, activation_condition = cond(P_PAD, padmode),
          source = note(n), glue = PRESS, target = reaper_action(command) }
    if on_colour then
        add { id = string.format("%s-p%d-padled-%d", group, padmode, k), name = string.format("pad %d state", k),
              group = group, control_enabled = false, activation_condition = cond(P_PAD, padmode),
              source = { kind = "MidiScript", script_kind = "Lua",
                         script = colour_script(n, col .. "\nif y ~= nil and y > 0 then c = " .. on_colour .. " end") },
              target = reaper_action(command) }
    else
        paint(group, padmode, k, col)
    end
end
local function focused_fx_param(index)
    return { kind = "FxParameterValue", parameter = { address = "ByIndex", fx = { address = "Focused" }, index = index } }
end

-- ---- fixed global controls: Mode buttons, knob-function buttons, master fader ----------------------
for cc, idx in pairs({ [57] = MODE_OFF, [58] = MODE_REC, [59] = MODE_SEL, [60] = MODE_MUTE, [61] = MODE_SOLO }) do
    add { id = "mode-" .. cc, name = "Mode button", group = "global", feedback_enabled = false,
          source = cc_button(15, cc), glue = { button_filter = "PressOnly", target_interval = { idx / 4, idx / 4 } }, target = param(P_MODE) }
    add { id = "mode-echo-" .. cc, name = "Mode button -> state echo", group = "global", feedback_enabled = false,
          source = cc_button(15, cc), glue = PRESS, target = send_to_port1(string.format("B0 %02X 7F", cc)) }
end
for cc, idx in pairs({ [85] = KNOB_PAN, [86] = KNOB_DEV, [87] = KNOB_SEND, [83] = KNOB_SELSEND }) do
    add { id = "knobmode-" .. cc, name = "Knob function button", group = "global", feedback_enabled = false,
          source = cc_button(15, cc), glue = { button_filter = "PressOnly", target_interval = { idx / 3, idx / 3 } }, target = param(P_KNOB) }
    add { id = "knobmode-echo-" .. cc, name = "Knob function -> state echo", group = "global", feedback_enabled = false,
          source = cc_button(15, cc), glue = PRESS, target = send_to_port1(string.format("B0 %02X 7F", cc)) }
end
add { id = "master", name = "Master volume", group = "global", feedback_enabled = false, source = cc_range(0, 41), glue = PICKUP,
      target = { kind = "TrackVolume", track = MASTER } }

-- ---- modifiers ----------------------------------------------------------------------------------
-- which modifiers define a combo for a given control (base mapping is gated on all of them being off)
local function modifiers_for(cid)
    local list = {}
    for _, mid in ipairs(ALL_MODIFIER_IDS) do
        local m = MODEL.modifiers and MODEL.modifiers[mid]
        if MODIFIER_PARAM[mid] and m then
            if cid == "encoder_turn" then
                if m.encoder_turn and m.encoder_turn.kind ~= "none" then table.insert(list, mid) end
            elseif m.combos and m.combos[cid] and m.combos[cid].kind ~= "none" then
                table.insert(list, mid)
            end
        end
    end
    return list
end
local function all_off(mids)
    if #mids == 0 then return nil end
    local mods = {}
    for _, mid in ipairs(mids) do table.insert(mods, { parameter = MODIFIER_PARAM[mid], on = false }) end
    return { kind = "Modifier", modifiers = mods }
end
local function armed(mid)
    return { kind = "Modifier", modifiers = { { parameter = MODIFIER_PARAM[mid], on = true } } }
end

for _, mid in ipairs(CONTROL_ORDER) do
    local pidx = MODIFIER_PARAM[mid]
    if pidx then
        local cc = CONTROL_CC[mid]
        local m = (MODEL.modifiers and MODEL.modifiers[mid]) or { combos = {} }
        -- latch: press toggles the layer
        add { id = "modstate-" .. mid, name = "Modifier layer (latch): " .. mid, group = "global", feedback_enabled = false,
              source = cc_button(0, cc), glue = { absolute_mode = "ToggleButton" }, target = param(pidx) }
        -- watcher echoes (CC 104 on port 1 = "a layer armed / dropped"; the pads show the indicator)
        if (MODEL.buttons[mid].indicator or "checkerboard") ~= "none" then
            add { id = "modarm-echo-" .. mid, name = "Layer armed -> watcher", group = "global", feedback_enabled = false,
                  activation_condition = { kind = "Modifier", modifiers = { { parameter = pidx, on = false } } },
                  source = cc_button(0, cc), glue = PRESS, target = send_to_port1("B0 68 7F") }
            add { id = "modcancel-echo-" .. mid, name = "Layer cancelled -> watcher", group = "global", feedback_enabled = false,
                  activation_condition = armed(mid), source = cc_button(0, cc), glue = PRESS, target = send_to_port1("B0 68 00") }
        end
        -- every button with a combo drops the layer after firing (and tells the watcher)
        for _, cid in ipairs(CONTROL_ORDER) do
            local combo = m.combos and m.combos[cid]
            if combo and combo.kind ~= "none" and cid ~= mid then
                add { id = string.format("moddrop-%s-%s", mid, cid), name = "Layer consumed", group = "global", feedback_enabled = false,
                      activation_condition = armed(mid), source = cc_button(0, CONTROL_CC[cid]),
                      glue = { button_filter = "PressOnly", target_interval = { 0, 0 } }, target = param(pidx) }
                if (MODEL.buttons[mid].indicator or "checkerboard") ~= "none" then
                    add { id = string.format("moddrop-echo-%s-%s", mid, cid), name = "Layer consumed -> watcher", group = "global", feedback_enabled = false,
                          activation_condition = armed(mid), source = cc_button(0, CONTROL_CC[cid]), glue = PRESS, target = send_to_port1("B0 68 00") }
                end
            end
        end
    end
end

-- external hold modifiers: the injected CC drives the parameter directly (127 -> held, 0 -> up); the pad indicator
-- follows the same press/release (no latch, no drop mappings)
for _, id in ipairs(EXTERNAL_IDS) do
    local e = MODEL.modifiers[id].external
    local ch = e.channel or 13
    add { id = "modstate-" .. id, name = "Modifier (hold): " .. (e.name or id), group = "global", feedback_enabled = false,
          source = cc_button(ch, e.cc), target = param(MODIFIER_PARAM[id]) }
    if (e.indicator or "checkerboard") ~= "none" then
        add { id = "modhold-echo-" .. id, name = "Hold modifier -> watcher", group = "global", feedback_enabled = false,
              source = cc_range(ch, e.cc), target = send_to_port1("B0 68 [0gfe dcba]") }
    end
end

-- ---- button assignments -------------------------------------------------------------------------
-- emits the mapping(s) for one assignment on one control; `condition` is the activation condition to use
local function emit_button(cid, a, condition, group, idprefix)
    local cc = CONTROL_CC[cid]
    local base = { group = group or "global", feedback_enabled = false, activation_condition = condition }
    local function m(id, name, fields)
        local t = { id = idprefix .. id, name = name }
        for k, v in pairs(base) do t[k] = v end
        for k, v in pairs(fields) do t[k] = v end
        add(t)
    end
    if a == nil or a.kind == "none" then return end
    if a.kind == "action" then
        m(cid, "Action " .. tostring(a.command), { source = cc_button(0, cc), glue = PRESS, target = reaper_action(a.command) })
    elseif a.kind == "builtin" then
        local b = a.builtin
        if b == "transport_play" then
            m(cid, "Play/Stop", { source = cc_button(0, cc), glue = TOGGLE, target = { kind = "TransportAction", action = "PlayStop" } })
        elseif b == "transport_stop" then
            m(cid, "Stop", { source = cc_button(0, cc), glue = PRESS, target = { kind = "TransportAction", action = "Stop" } })
        elseif b == "transport_record" then
            m(cid, "Record", { source = cc_button(0, cc), glue = TOGGLE, target = { kind = "TransportAction", action = "Record" } })
        elseif b == "transport_loop" then
            m(cid, "Repeat", { source = cc_button(0, cc), glue = TOGGLE, target = { kind = "TransportAction", action = "Repeat" } })
        elseif b == "bank_prev" or b == "bank_next" then
            m(cid, b == "bank_prev" and "Bank <" or "Bank >", { source = cc_button(0, cc),
                glue = { absolute_mode = "IncrementalButton", reverse = (b == "bank_prev") or nil, step_factor_interval = { 1, 1 } }, target = param(P_BANK) })
            m(cid .. "-echo", "Bank press -> watcher", { source = cc_button(0, cc), glue = PRESS,
                target = send_to_port1(b == "bank_prev" and "B0 6E 7F" or "B0 6F 7F") })
        elseif b == "padmode_prev" or b == "padmode_next" then
            m(cid, b == "padmode_prev" and "Pad mode <" or "Pad mode >", { source = cc_button(0, cc),
                glue = { absolute_mode = "IncrementalButton", reverse = (b == "padmode_prev") or nil, wrap = true, step_factor_interval = { 1, 1 } }, target = param(P_PAD) })
            m(cid .. "-echo", "Pad mode press -> state echo", { source = cc_button(0, cc), glue = PRESS,
                target = send_to_port1(b == "padmode_prev" and "B0 6B 7F" or "B0 6C 7F") })
        elseif b == "layout_toggle" then
            m(cid, "Layout toggle", { source = cc_button(0, cc),
                glue = { absolute_mode = "IncrementalButton", wrap = true, step_factor_interval = { 1, 1 } }, target = param(P_LAYOUT) })
            m(cid .. "-echo", "Layout press -> watcher", { source = cc_button(0, cc), glue = PRESS, target = send_to_port1("B0 71 7F") })
        elseif b == "tap_tempo" then
            m(cid, "Tap tempo -> watcher", { source = cc_button(0, cc), glue = PRESS, target = send_to_port1("B0 66 7F") })
        end
    end
end

local function emit_encoder(a, condition, idprefix)
    local base = { group = "global", feedback_enabled = false, activation_condition = condition }
    local src = { kind = "MidiControlChangeValue", channel = 0, controller_number = ENCODER_CC, character = "Relative2" }
    local function m(id, name, fields)
        local t = { id = idprefix .. id, name = name }
        for k, v in pairs(base) do t[k] = v end
        for k, v in pairs(fields) do t[k] = v end
        add(t)
    end
    if a == nil or a.kind == "none" then return end
    if a.kind == "browse_tracks" then
        m("encoder", "Browse tracks", { source = src, target = { kind = "BrowseTracks", scroll_arrange_view = true, scroll_mixer = true } })
    elseif a.kind == "zoom" then
        m("encoder-zoom-in",  "Encoder = zoom in (1012)",  { source = src, glue = { encoder_filter = "IncrementOnly" }, target = reaper_action(1012) })
        m("encoder-zoom-out", "Encoder = zoom out (1011)", { source = src, glue = { encoder_filter = "DecrementOnly" }, target = reaper_action(1011) })
    elseif a.kind == "actions" then
        m("encoder-cw",  "Encoder clockwise " .. tostring(a.cw),      { source = src, glue = { encoder_filter = "IncrementOnly" }, target = reaper_action(a.cw) })
        m("encoder-ccw", "Encoder anticlockwise " .. tostring(a.ccw), { source = src, glue = { encoder_filter = "DecrementOnly" }, target = reaper_action(a.ccw) })
    end
end

-- base assignments (gated on every modifier that overrides the control being off)
for _, cid in ipairs(CONTROL_ORDER) do
    local a = MODEL.buttons[cid]
    if a and a.kind ~= "modifier" then
        emit_button(cid, a, all_off(modifiers_for(cid)), "global", "")
    end
end
emit_encoder(MODEL.encoder_turn, all_off(modifiers_for("encoder_turn")), "")

-- combos (active while the modifier layer is armed or the hold modifier is down)
for _, mid in ipairs(ALL_MODIFIER_IDS) do
    local m = MODEL.modifiers and MODEL.modifiers[mid]
    if MODIFIER_PARAM[mid] and m then
        for _, cid in ipairs(CONTROL_ORDER) do
            local combo = m.combos and m.combos[cid]
            if combo and cid ~= mid then
                if combo.kind == "per_layout" then
                    for li, lay in ipairs(MODEL.layouts) do
                        local la = combo.layouts and combo.layouts[lay.id]
                        if la then emit_button(cid, la, armed(mid), "lay" .. (li - 1), "mod-" .. mid .. "-" .. lay.id .. "-") end
                    end
                else
                    emit_button(cid, combo, armed(mid), "global", "mod-" .. mid .. "-")
                end
            end
        end
        if m.encoder_turn then emit_encoder(m.encoder_turn, armed(mid), "mod-" .. mid .. "-") end
    end
end

-- ---- fader banks ---------------------------------------------------------------------------------
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
local function focused_fx_bank(group)
    for i = 0, 7 do
        add { id = string.format("%s-fader-%d", group, i + 1), name = string.format("Focused FX param %d", i + 1),
              group = group, feedback_enabled = false, source = cc_range(0, 12 + i), glue = PICKUP, target = focused_fx_param(i) }
        add { id = string.format("%s-knob-%d", group, i + 1), name = string.format("Focused FX param %d", i + 9),
              group = group, feedback_enabled = false, source = cc_range(0, 22 + i), glue = PICKUP, target = focused_fx_param(8 + i) }
    end
    local sel_mute_row = {
        { kind = "TrackMuteState", track = SELECTED },
        { kind = "TrackSoloState", track = SELECTED },
        { kind = "TrackArmState", track = SELECTED },
        { kind = "AllTrackFxOnOffState", track = SELECTED },
    }
    fader_button_row(group, function(mode, i)
        if mode == MODE_SEL then
            return { kind = "FxOnOffState", fx = { address = "ByIndex", chain = { address = "Track", track = SELECTED }, index = i } }
        elseif mode == MODE_MUTE then
            return sel_mute_row[i + 1]
        end
        return nil
    end)
end
for i, b in ipairs(MODEL.banks) do
    local group = "bank" .. i
    if b.kind == "tracks" then mixer_bank(group, b.first_track or 0)
    elseif b.kind == "focused_fx" then focused_fx_bank(group)
    else fader_button_row(group, function(mode, i) return nil end) end
end

-- ---- pad modes ------------------------------------------------------------------------------------
local function drums(group, padmode)
    for k = 1, 16 do
        local n = PAD_NOTE[k]
        add { id = string.format("%s-p%d-inject-%d", group, padmode, k), name = string.format("Pad %d -> port 1 ch10 note %d", k, n),
              group = group, feedback_enabled = false, activation_condition = cond(P_PAD, padmode), source = note(n),
              target = send_to_port1(string.format("99 %02X [0gfe dcba]", n)) }
        add { id = string.format("%s-p%d-vel-%d", group, padmode, k), name = string.format("Pad %d velocity", k),
              group = group, feedback_enabled = false, activation_condition = cond(P_PAD, padmode), source = note(n), target = param(P_VEL0 + k - 1) }
        add { id = string.format("%s-p%d-led-%d", group, padmode, k), name = string.format("Pad %d colour", k),
              group = group, control_enabled = false, activation_condition = cond(P_PAD, padmode),
              source = { kind = "MidiScript", script_kind = "Lua",
                         script = colour_script(n, C.blue .. "\nif y ~= nil and y > 0 then\n  if y < 0.34 then c = " .. C.green
                             .. "\n  elseif y < 0.67 then c = " .. C.yellow .. "\n  else c = " .. C.red .. " end\nend") },
              target = param(P_VEL0 + k - 1) }
    end
end
local function mixer_grid(group, padmode, first_track)
    for k = 1, 8 do
        state_pad(group, padmode, k,     { kind = "TrackMuteState", track = track(first_track + k - 1) }, C.red, C.chartreuse)
        state_pad(group, padmode, k + 8, { kind = "TrackSoloState", track = track(first_track + k - 1) }, C.yellow, C.azure)
    end
end
local function custom_pads(group, padmode, pads)
    for k = 1, 16 do
        local p = pads and pads[k]
        if p == nil or p.kind == nil or p.kind == "none" then
            paint(group, padmode, k, colour(p and p.colour or "off"))
        elseif p.kind == "action" then
            action_pad(group, padmode, k, p.command, colour(p.colour), p.on_colour and colour(p.on_colour) or nil)
        elseif p.kind == "transport" then
            state_pad(group, padmode, k, { kind = "TransportAction", action = p.action }, colour(p.on_colour or "yellow"), colour(p.colour or "azure"))
        elseif p.kind == "track_state" then
            local trk = track(p.track or 0)
            local tgt
            if p.state == "mute" then tgt = { kind = "TrackMuteState", track = trk }
            elseif p.state == "solo" then tgt = { kind = "TrackSoloState", track = trk }
            elseif p.state == "arm" then tgt = { kind = "TrackArmState", track = trk }
            else tgt = { kind = "TrackSelectionState", track = trk, scroll_arrange_view = true, scroll_mixer = true } end
            state_pad(group, padmode, k, tgt, colour(p.on_colour or "red"), colour(p.colour or "chartreuse"))
        end
    end
end
local function emit_pad_mode(group, padmode, pm)
    if pm.kind == "drums" then drums(group, padmode)
    elseif pm.kind == "mixer" then mixer_grid(group, padmode, pm.first_track or 0)
    elseif pm.kind == "custom" then custom_pads(group, padmode, pm.pads)
    else for k = 1, 16 do paint(group, padmode, k, colour(pm.colour or "white")) end end
end
for li, lay in ipairs(MODEL.layouts) do
    for mi, pm in ipairs(lay.pad_modes) do
        emit_pad_mode("lay" .. (li - 1), mi - 1, pm)
    end
end

return { parameters = parameters, groups = groups, mappings = mappings }

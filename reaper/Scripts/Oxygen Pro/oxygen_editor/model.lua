-- Oxygen Pro 61 editor: the layout model.
--
-- A model is a plain table (saved as JSON) that fully describes what every control on the keyboard does.
-- The generator turns it into a ReaLearn Luau preset (see generator.lua + interpreter.luau).
-- `model.default()` is the shipped layout (one "General DAW" layout). Add layouts, pad modes, banks and modifiers in the editor;
-- a second layout with per-layout Back combos is a supported shape (`kind = "per_layout"` assignments).

local M = {}

-- ---- catalogues ---------------------------------------------------------------------------------
M.COLOURS = { off = 0, red = 3, orange = 11, green = 12, chartreuse = 14, yellow = 15, rose = 35,
              aqua = 44, blue = 48, violet = 50, magenta = 51, azure = 56, cyan = 60, white = 63 }
M.COLOUR_ORDER = { "off", "red", "orange", "yellow", "chartreuse", "green", "cyan", "aqua", "azure", "blue", "violet", "magenta", "rose", "white" }

-- Button-like controls on port 3 that can be assigned freely (id, label, CC on channel 1)
M.CONTROLS = {
    { id = "play",          name = "Play",           cc = 118 },
    { id = "stop",          name = "Stop",           cc = 117 },
    { id = "record",        name = "Record",         cc = 119 },
    { id = "loop",          name = "Loop",           cc = 114 },
    { id = "rewind",        name = "<<",             cc = 115 },
    { id = "ffwd",          name = ">>",             cc = 116 },
    { id = "bank_prev",     name = "Bank <",         cc = 110 },
    { id = "bank_next",     name = "Bank >",         cc = 111 },
    { id = "side_top",      name = "Pad side (top)", cc = 107 },
    { id = "side_bottom",   name = "Pad side (bottom)", cc = 108 },
    { id = "encoder_press", name = "Encoder press",  cc = 102 },
    { id = "back",          name = "Back",           cc = 104 },
    { id = "daw",           name = "DAW",            cc = 113 },
}
M.CONTROL_BY_ID = {}
for _, c in ipairs(M.CONTROLS) do M.CONTROL_BY_ID[c.id] = c end
M.ENCODER_CC = 103

-- Built-in behaviours a button can have (besides "action" and "modifier")
M.BUILTINS = {
    { id = "none",             name = "Nothing" },
    { id = "transport_play",   name = "Play / stop (toggle)" },
    { id = "transport_stop",   name = "Stop" },
    { id = "transport_record", name = "Record (toggle)" },
    { id = "transport_loop",   name = "Repeat (toggle)" },
    { id = "bank_prev",        name = "Fader bank -" },
    { id = "bank_next",        name = "Fader bank +" },
    { id = "padmode_prev",     name = "Pad mode - (wraps)" },
    { id = "padmode_next",     name = "Pad mode + (wraps)" },
    { id = "layout_toggle",    name = "Next layout (wraps, pad sweep)" },
    { id = "tap_tempo",        name = "Tap tempo (watcher sets BPM)" },
}
M.BUILTIN_BY_ID = {}
for _, b in ipairs(M.BUILTINS) do M.BUILTIN_BY_ID[b.id] = b end

-- Encoder-turn behaviours
M.ENCODER_KINDS = {
    { id = "none",          name = "Nothing" },
    { id = "browse_tracks", name = "Browse tracks (selection follows)" },
    { id = "zoom",          name = "Zoom arrange view (1011 / 1012)" },
    { id = "actions",       name = "Two actions (clockwise / anticlockwise)" },
}

-- Pad-mode kinds
M.PAD_MODE_KINDS = {
    { id = "drums",  name = "Drums: hits to port 1 ch 10, velocity colours" },
    { id = "mixer",  name = "Mixer: pads 1-8 mute, 9-16 solo of 8 tracks" },
    { id = "custom", name = "Custom: each pad its own function" },
    { id = "free",   name = "Free: nothing mapped, one colour" },
}
-- Pad assignment kinds inside a custom pad mode
M.PAD_KINDS = {
    { id = "none",        name = "Nothing (just a colour)" },
    { id = "action",      name = "REAPER action (trigger)" },
    { id = "transport",   name = "Transport toggle (Play/Stop, Stop, Record, Repeat)" },
    { id = "track_state", name = "Track state toggle (mute / solo / arm / select)" },
}
M.TRANSPORT_ACTIONS = { "PlayStop", "Stop", "Record", "Repeat" }
M.TRACK_STATES = { "mute", "solo", "arm", "select" }

-- Fader-bank kinds
M.BANK_KINDS = {
    { id = "tracks",     name = "8 tracks: faders volume, knobs pan/FX/sends, buttons arm/select/mute/solo" },
    { id = "focused_fx", name = "Focused FX: faders params 1-8, knobs 9-16, buttons FX slots / selected-track states" },
    { id = "free",       name = "Free: nothing mapped, LEDs dark" },
}

M.MODIFIER_INDICATORS = { { id = "checkerboard", name = "Violet/rose checkerboard on the pads" }, { id = "none", name = "No pad indicator" } }

-- External HOLD modifiers: a message from another device (e.g. a foot switch) that another ReaLearn unit injects into
-- the MIDIIN3 input as a CC on channel 14 (0-based 13). 127 = held, 0 = released. Unlike the keyboard's buttons this is a
-- real hold: combos fire while the foot is down, nothing is latched. They live in model.modifiers[id] with an
-- `external = { name, cc, channel }` block instead of a button assignment.
M.EXTERNAL_CHANNEL = 13
function M.is_external_modifier(model, id)
    local m = model.modifiers and model.modifiers[id]
    return type(m) == "table" and type(m.external) == "table"
end
-- all modifier ids in a stable order: modifier buttons first (control order), then external ones (sorted)
function M.modifier_ids(model)
    local ids = {}
    for _, c in ipairs(M.CONTROLS) do
        local a = model.buttons and model.buttons[c.id]
        if a and a.kind == "modifier" then ids[#ids + 1] = c.id end
    end
    local ext = {}
    for id, m in pairs(model.modifiers or {}) do if type(m) == "table" and type(m.external) == "table" then ext[#ext + 1] = id end end
    table.sort(ext)
    for _, id in ipairs(ext) do ids[#ids + 1] = id end
    return ids
end
function M.modifier_name(model, id)
    if M.is_external_modifier(model, id) then return model.modifiers[id].external.name or id end
    return M.CONTROL_BY_ID[id] and M.CONTROL_BY_ID[id].name or id
end

-- ---- Exquis (optional second surface) ------------------------------------------------------------
M.EXQUIS_RGB = { "green", "red", "yellow", "violet", "azure", "white", "orange", "cyan", "magenta", "off" }
M.EXQUIS_BUTTONS = {
    { id = "play",   name = "Play/Stop", elem = 105 }, { id = "record", name = "Record", elem = 102 },
    { id = "loop",   name = "Loop",      elem = 103 }, { id = "clips",  name = "Clips",  elem = 104 },
    { id = "undo",   name = "Undo",      elem = 108 }, { id = "redo",   name = "Redo",   elem = 109 },
    { id = "down",   name = "Down",      elem = 106 }, { id = "up",     name = "Up",     elem = 107 },
}
M.EXQUIS_BUTTON_BUILTINS = {
    { id = "transport_play", name = "Play / stop (toggle, LED = playing)" }, { id = "transport_record", name = "Record (toggle, LED = armed)" },
    { id = "transport_loop", name = "Repeat (toggle, LED = on)" }, { id = "transport_stop", name = "Stop" }, { id = "tap_tempo", name = "Tap tempo (Oxygen watcher)" },
    { id = "mode_next", name = "Next Exquis mode (LED = mode colour)" }, { id = "mode_prev", name = "Previous Exquis mode (LED = mode colour)" },
}
M.EXQUIS_SLIDER_MODES = { { id = "native", name = "Native: the keyboard's arpeggiator rate slider" }, { id = "zones", name = "Six zones as buttons (REAPER)" } }
M.EXQUIS_ENCODER_KINDS = {
    { id = "none", name = "Nothing" }, { id = "selected_volume", name = "Selected track volume" }, { id = "selected_pan", name = "Selected track pan" },
    { id = "master_volume", name = "Master volume" }, { id = "selected_send", name = "Selected track send N" }, { id = "browse_tracks", name = "Browse tracks" },
    { id = "tempo", name = "Project tempo" }, { id = "fx_param", name = "Focused FX parameter N" }, { id = "zoom", name = "Zoom arrange view" },
    { id = "actions", name = "Two actions (clockwise / anticlockwise)" },
}
M.EXQUIS_PUSH_KINDS = {
    { id = "none", name = "Nothing" }, { id = "selected_mute", name = "Mute selected track (LED)" }, { id = "selected_solo", name = "Solo selected track (LED)" },
    { id = "selected_arm", name = "Arm selected track (LED)" }, { id = "tap_tempo", name = "Tap tempo (Oxygen watcher)" },
    { id = "action", name = "REAPER action" }, { id = "transport", name = "Transport toggle" },
    { id = "mode_next", name = "Next Exquis mode" }, { id = "mode_prev", name = "Previous Exquis mode" },
}
M.EXQUIS_SLIDER_KINDS = { { id = "none", name = "Nothing" }, { id = "action", name = "REAPER action" }, { id = "transport", name = "Transport toggle" } }

-- one Exquis "mode": a full set of assignments (like an Oxygen pad mode / layout)
function M.exquis_mode_track()
    local function act(cmd, col) return { kind = "action", command = cmd, colour = col } end
    local slider = {}
    for k = 1, 6 do slider[k] = act(40160 + k, "orange") end
    return {
        name = "Track", colour = "white",
        buttons = {
            play = { kind = "builtin", builtin = "transport_play", colour = "green" },
            record = { kind = "builtin", builtin = "transport_record", colour = "red" },
            loop = { kind = "builtin", builtin = "transport_loop", colour = "yellow" },
            clips = { kind = "builtin", builtin = "mode_next" }, undo = act(40029, "violet"), redo = act(40030, "violet"),
            down = act(40286, "azure"), up = act(40285, "azure"),
        },
        encoders = {
            { kind = "selected_volume", colour = "green" }, { kind = "selected_pan", colour = "azure" },
            { kind = "browse_tracks", colour = "white" }, { kind = "tempo", colour = "orange" },
        },
        pushes = {
            { kind = "selected_mute", colour = "red" }, { kind = "selected_solo", colour = "yellow" },
            { kind = "selected_arm", colour = "red" }, { kind = "tap_tempo", colour = "white" },
        },
        slider = slider,
        shift = {
            buttons = {
                play = act(40157, "white"), record = act(40364, "magenta"), loop = act(40078, "cyan"), clips = act(40026, "green"),
                undo = act(40172, "orange"), redo = act(40173, "orange"), down = act(1011, "cyan"), up = act(1012, "cyan"),
            },
            encoders = {
                { kind = "master_volume", colour = "red" }, { kind = "selected_send", index = 0, colour = "yellow" },
                { kind = "zoom", colour = "cyan" }, { kind = "none", colour = "orange", dim = true },
            },
        },
    }
end
function M.exquis_mode_device()
    local function act(cmd, col) return { kind = "action", command = cmd, colour = col } end
    return {
        name = "Device", colour = "cyan",
        buttons = {
            play = { kind = "builtin", builtin = "transport_play", colour = "green" },
            record = { kind = "builtin", builtin = "transport_record", colour = "red" },
            loop = { kind = "builtin", builtin = "transport_loop", colour = "yellow" },
            clips = { kind = "builtin", builtin = "mode_next" }, undo = act(40029, "violet"), redo = act(40030, "violet"),
            down = act(40286, "azure"), up = act(40285, "azure"),
        },
        encoders = {
            { kind = "fx_param", index = 0, colour = "cyan" }, { kind = "fx_param", index = 1, colour = "cyan" },
            { kind = "fx_param", index = 2, colour = "cyan" }, { kind = "fx_param", index = 3, colour = "cyan" },
        },
        pushes = {
            { kind = "selected_mute", colour = "red" }, { kind = "selected_solo", colour = "yellow" },
            { kind = "selected_arm", colour = "red" }, { kind = "tap_tempo", colour = "white" },
        },
        slider = {},
        shift = { buttons = {}, encoders = {
            { kind = "fx_param", index = 4, colour = "azure" }, { kind = "fx_param", index = 5, colour = "azure" },
            { kind = "fx_param", index = 6, colour = "azure" }, { kind = "fx_param", index = 7, colour = "azure" },
        } },
    }
end
function M.exquis_default()
    return {
        enabled = false,                      -- the public default ships it off; the first-time setup turns it on when an Exquis is found
        shift_cc = 105, shift_channel = 13,   -- the FCB1010 bridge's hold shift, same as the keyboard
        port1_input_device = 14,
        slider_mode = "native",               -- the slider stays the keyboard's arpeggiator-rate slider; "zones" gives six REAPER buttons
        modes = { M.exquis_mode_track(), M.exquis_mode_device() },
    }
end
-- older saved models had one flat set of assignments; lift it into modes[1]
function M.exquis_migrate(x)
    if type(x) ~= "table" then return x end
    if x.modes == nil and (x.buttons or x.encoders) then
        x.modes = { { name = "Track", colour = "white", buttons = x.buttons, encoders = x.encoders, pushes = x.pushes, slider = x.slider, shift = x.shift } }
        x.buttons, x.encoders, x.pushes, x.slider, x.shift = nil, nil, nil, nil, nil
        x.slider_mode = x.slider_mode or "zones"
    end
    return x
end

local function exquis_colour_ok(a)
    if a == nil or a.colour == nil then return true end
    for _, c in ipairs(M.EXQUIS_RGB) do if c == a.colour then return true end end
    return false
end
local function is_command_value(v)
    return (type(v) == "number" and v > 0) or (type(v) == "string" and v:match("^_[%w_]+$") ~= nil)
end
function M.validate_exquis(x, errors)
    if x == nil then return end
    if type(x) ~= "table" then errors[#errors + 1] = "exquis must be a table"; return end
    local function check_button(a, where)
        if a == nil then return end
        if not exquis_colour_ok(a) then errors[#errors + 1] = where .. ": unknown colour" end
        if a.kind == "action" then
            if not is_command_value(a.command) then errors[#errors + 1] = where .. ": bad command" end
        elseif a.kind == "builtin" then
            local ok = false
            for _, b in ipairs(M.EXQUIS_BUTTON_BUILTINS) do if b.id == a.builtin then ok = true end end
            if not ok then errors[#errors + 1] = where .. ": unknown builtin" end
        elseif a.kind ~= "none" and a.kind ~= nil then errors[#errors + 1] = where .. ": unknown kind" end
    end
    local function check_encoder(a, where)
        if a == nil then return end
        if not exquis_colour_ok(a) then errors[#errors + 1] = where .. ": unknown colour" end
        local ok = false
        for _, k in ipairs(M.EXQUIS_ENCODER_KINDS) do if k.id == a.kind then ok = true end end
        if not ok then errors[#errors + 1] = where .. ": unknown kind" end
        if a.kind == "actions" and not (is_command_value(a.cw) and is_command_value(a.ccw)) then errors[#errors + 1] = where .. ": cw and ccw commands required" end
    end
    M.exquis_migrate(x)
    if x.slider_mode ~= nil and x.slider_mode ~= "native" and x.slider_mode ~= "zones" then errors[#errors + 1] = "exquis.slider_mode must be native or zones" end
    if type(x.modes) ~= "table" or #x.modes < 1 then errors[#errors + 1] = "exquis needs at least one mode"; return end
    if #x.modes > 8 then errors[#errors + 1] = "exquis: at most 8 modes" end
    for mi, x in ipairs(x.modes) do
        local pre = "exquis.modes." .. mi .. "."
        if x.colour and not exquis_colour_ok(x) then errors[#errors + 1] = pre .. "colour unknown" end
        for _, b in ipairs(M.EXQUIS_BUTTONS) do
            check_button(x.buttons and x.buttons[b.id], pre .. "buttons." .. b.id)
            check_button(x.shift and x.shift.buttons and x.shift.buttons[b.id], pre .. "shift.buttons." .. b.id)
        end
        for i = 1, 4 do
            check_encoder(x.encoders and x.encoders[i], pre .. "encoders." .. i)
            check_encoder(x.shift and x.shift.encoders and x.shift.encoders[i], pre .. "shift.encoders." .. i)
            local pu = x.pushes and x.pushes[i]
            if pu ~= nil then
                local ok = false
                for _, k in ipairs(M.EXQUIS_PUSH_KINDS) do if k.id == pu.kind then ok = true end end
                if not ok then errors[#errors + 1] = pre .. "pushes." .. i .. ": unknown kind" end
                if pu.kind == "action" and not is_command_value(pu.command) then errors[#errors + 1] = pre .. "pushes." .. i .. ": bad command" end
                if not exquis_colour_ok(pu) then errors[#errors + 1] = pre .. "pushes." .. i .. ": unknown colour" end
            end
        end
        for k = 1, 6 do
            local sl = x.slider and x.slider[k]
            if sl ~= nil then
                local ok = false
                for _, kk in ipairs(M.EXQUIS_SLIDER_KINDS) do if kk.id == sl.kind then ok = true end end
                if not ok then errors[#errors + 1] = pre .. "slider." .. k .. ": unknown kind" end
                if sl.kind == "action" and not is_command_value(sl.command) then errors[#errors + 1] = pre .. "slider." .. k .. ": bad command" end
                if not exquis_colour_ok(sl) then errors[#errors + 1] = pre .. "slider." .. k .. ": unknown colour" end
            end
        end
    end
end

-- ---- default model = the hand-built layout ------------------------------------------------------
local function action(command, colour, on_colour)
    return { kind = "action", command = command, colour = colour, on_colour = on_colour }
end

function M.default()
    local markers = {}
    for k = 1, 8 do markers[k] = action(40160 + k, "orange") end
    markers[9]  = action(40157, "white")
    markers[10] = action(40172, "azure")
    markers[11] = action(40173, "azure")
    markers[12] = { kind = "transport", action = "Repeat", colour = "azure", on_colour = "yellow" }
    markers[13] = action(40029, "violet")
    markers[14] = action(40030, "violet")
    markers[15] = action(40026, "green")
    markers[16] = action(40364, "off", "magenta")

    return {
        version = 1,
        port1_input_device = 14,
        off_mode_local_leds = true,   -- Off mode: LEDs 1-4 show the keyboard's ARP / Latch / Chord / Scale toggles
        exquis = M.exquis_default(),  -- optional second surface, off until enabled
        layouts = {
            { id = "general", name = "General DAW", sweep_colour = "green",
              pad_modes = {
                  { name = "Drums",       kind = "drums" },
                  { name = "Mixer 1-8",   kind = "mixer", first_track = 0 },
                  { name = "Mixer 9-16",  kind = "mixer", first_track = 8 },
                  { name = "Markers",     kind = "custom", pads = markers },
                  { name = "Free",        kind = "free", colour = "white" },
              } },
        },
        banks = {
            { name = "Bank 1: tracks 1-8",          kind = "tracks", first_track = 0 },
            { name = "Bank 2: selected track / FX", kind = "focused_fx" },
            { name = "Bank 3: tracks 9-16",         kind = "tracks", first_track = 8 },
            { name = "Bank 4: free",                kind = "free" },
        },
        buttons = {
            play          = { kind = "builtin", builtin = "transport_play" },
            stop          = { kind = "builtin", builtin = "transport_stop" },
            record        = { kind = "builtin", builtin = "transport_record" },
            loop          = { kind = "builtin", builtin = "transport_loop" },
            rewind        = { kind = "action", command = 40042 },
            ffwd          = { kind = "action", command = 40043 },
            bank_prev     = { kind = "builtin", builtin = "bank_prev" },
            bank_next     = { kind = "builtin", builtin = "bank_next" },
            side_top      = { kind = "builtin", builtin = "padmode_prev" },
            side_bottom   = { kind = "builtin", builtin = "padmode_next" },
            encoder_press = { kind = "builtin", builtin = "tap_tempo" },
            daw           = { kind = "builtin", builtin = "layout_toggle" },
            back          = { kind = "modifier", indicator = "checkerboard" },
        },
        encoder_turn = { kind = "browse_tracks" },
        modifiers = {
            back = {
                combos = {
                    rewind        = { kind = "action", command = 40029 },
                    ffwd          = { kind = "action", command = 40030 },
                    bank_prev     = { kind = "action", command = 40172 },
                    bank_next     = { kind = "action", command = 40173 },
                    play          = { kind = "action", command = 40157 },
                    record        = { kind = "action", command = 40364 },
                    loop          = { kind = "action", command = 40078 },
                    stop          = { kind = "action", command = 40026 },
                    encoder_press = { kind = "action", command = 40001 },
                },
                encoder_turn = { kind = "zoom" },
            },
        },
    }
end

-- ---- validation ---------------------------------------------------------------------------------
local function is_command(v) return (type(v) == "number" and v == math.floor(v) and v > 0) or (type(v) == "string" and v:match("^_[%w_]+$") ~= nil) end

local function check_button_assignment(a, where, errors, allow_modifier)
    if type(a) ~= "table" then errors[#errors + 1] = where .. ": missing assignment"; return end
    if a.kind == "builtin" then
        if not M.BUILTIN_BY_ID[a.builtin] then errors[#errors + 1] = where .. ": unknown builtin '" .. tostring(a.builtin) .. "'" end
    elseif a.kind == "action" then
        if not is_command(a.command) then errors[#errors + 1] = where .. ": command must be a positive integer or a _NAMED command" end
    elseif a.kind == "modifier" then
        if not allow_modifier then errors[#errors + 1] = where .. ": a combo cannot be a modifier" end
    elseif a.kind == "none" then
    elseif a.kind == "per_layout" then
        if not allow_modifier == false then end
        if type(a.layouts) ~= "table" then errors[#errors + 1] = where .. ": per_layout needs layouts" end
    else
        errors[#errors + 1] = where .. ": unknown kind '" .. tostring(a.kind) .. "'"
    end
end

function M.validate(model)
    local errors = {}
    if type(model) ~= "table" then return { "model is not a table" } end
    if type(model.layouts) ~= "table" or #model.layouts < 1 then errors[#errors + 1] = "at least one layout is required" end
    local nmodes
    local layout_ids = {}
    for li, lay in ipairs(model.layouts or {}) do
        local where = "layout " .. li
        if type(lay.id) ~= "string" or lay.id == "" then errors[#errors + 1] = where .. ": id required" end
        if layout_ids[lay.id] then errors[#errors + 1] = where .. ": duplicate id" end
        layout_ids[lay.id] = true
        if not M.COLOURS[lay.sweep_colour or "green"] then errors[#errors + 1] = where .. ": unknown sweep colour" end
        if type(lay.pad_modes) ~= "table" or #lay.pad_modes < 1 then errors[#errors + 1] = where .. ": at least one pad mode"
        else
            if nmodes == nil then nmodes = #lay.pad_modes
            elseif nmodes ~= #lay.pad_modes then errors[#errors + 1] = where .. ": every layout must have the same number of pad modes (" .. nmodes .. ")" end
            for mi, pm in ipairs(lay.pad_modes) do
                local w = where .. " pad mode " .. mi
                if pm.kind == "mixer" then
                    if type(pm.first_track) ~= "number" or pm.first_track < 0 then errors[#errors + 1] = w .. ": first_track >= 0 required" end
                elseif pm.kind == "free" then
                    if not M.COLOURS[pm.colour or "white"] then errors[#errors + 1] = w .. ": unknown colour" end
                elseif pm.kind == "custom" then
                    for k = 1, 16 do
                        local p = (pm.pads or {})[k]
                        if p ~= nil then
                            local pw = w .. " pad " .. k
                            if p.colour and not M.COLOURS[p.colour] then errors[#errors + 1] = pw .. ": unknown colour" end
                            if p.on_colour and not M.COLOURS[p.on_colour] then errors[#errors + 1] = pw .. ": unknown on colour" end
                            if p.kind == "action" then
                                if not is_command(p.command) then errors[#errors + 1] = pw .. ": bad command" end
                            elseif p.kind == "transport" then
                                local ok = false
                                for _, t in ipairs(M.TRANSPORT_ACTIONS) do if t == p.action then ok = true end end
                                if not ok then errors[#errors + 1] = pw .. ": bad transport action" end
                            elseif p.kind == "track_state" then
                                local ok = false
                                for _, t in ipairs(M.TRACK_STATES) do if t == p.state then ok = true end end
                                if not ok then errors[#errors + 1] = pw .. ": bad track state" end
                                if type(p.track) ~= "number" or p.track < 0 then errors[#errors + 1] = pw .. ": track index >= 0 required" end
                            elseif p.kind ~= "none" and p.kind ~= nil then
                                errors[#errors + 1] = pw .. ": unknown pad kind '" .. tostring(p.kind) .. "'"
                            end
                        end
                    end
                elseif pm.kind ~= "drums" then
                    errors[#errors + 1] = w .. ": unknown pad mode kind '" .. tostring(pm.kind) .. "'"
                end
            end
        end
    end
    if type(model.banks) ~= "table" or #model.banks < 1 or #model.banks > 8 then errors[#errors + 1] = "1 to 8 fader banks required" end
    for bi, b in ipairs(model.banks or {}) do
        if b.kind == "tracks" then
            if type(b.first_track) ~= "number" or b.first_track < 0 then errors[#errors + 1] = "bank " .. bi .. ": first_track >= 0 required" end
        elseif b.kind ~= "focused_fx" and b.kind ~= "free" then
            errors[#errors + 1] = "bank " .. bi .. ": unknown kind '" .. tostring(b.kind) .. "'"
        end
    end
    local buttons = model.buttons or {}
    local modifier_count = 0
    for _, c in ipairs(M.CONTROLS) do
        check_button_assignment(buttons[c.id], "button " .. c.id, errors, true)
        if type(buttons[c.id]) == "table" and buttons[c.id].kind == "modifier" then modifier_count = modifier_count + 1 end
    end
    local et = model.encoder_turn or { kind = "none" }
    if et.kind == "actions" then
        if not is_command(et.cw) or not is_command(et.ccw) then errors[#errors + 1] = "encoder_turn: cw and ccw commands required" end
    elseif et.kind ~= "none" and et.kind ~= "browse_tracks" and et.kind ~= "zoom" then
        errors[#errors + 1] = "encoder_turn: unknown kind '" .. tostring(et.kind) .. "'"
    end
    for mid, m in pairs(model.modifiers or {}) do
        if type(m) == "table" and type(m.external) == "table" then
            local e = m.external
            if type(mid) ~= "string" or not mid:match("^[%w_]+$") then errors[#errors + 1] = "external modifier id must be letters/digits/underscore" end
            if type(e.cc) ~= "number" or e.cc < 0 or e.cc > 127 then errors[#errors + 1] = "modifiers." .. tostring(mid) .. ": external cc must be 0-127" end
            if e.channel ~= nil and (type(e.channel) ~= "number" or e.channel < 0 or e.channel > 15) then errors[#errors + 1] = "modifiers." .. tostring(mid) .. ": external channel must be 0-15" end
            modifier_count = modifier_count + 1
        elseif not (buttons[mid] and buttons[mid].kind == "modifier") then errors[#errors + 1] = "modifiers." .. mid .. ": button is not declared as a modifier" end
        for cid, a in pairs(m.combos or {}) do
            if not M.CONTROL_BY_ID[cid] then errors[#errors + 1] = "modifiers." .. mid .. ": unknown control '" .. tostring(cid) .. "'"
            elseif cid == mid then errors[#errors + 1] = "modifiers." .. mid .. ": a modifier cannot combine with itself"
            else
                if a.kind == "per_layout" then
                    for lid, la in pairs(a.layouts or {}) do
                        if not layout_ids[lid] then errors[#errors + 1] = "modifiers." .. mid .. "." .. cid .. ": unknown layout '" .. tostring(lid) .. "'" end
                        check_button_assignment(la, "modifiers." .. mid .. "." .. cid .. "." .. lid, errors, false)
                    end
                else
                    check_button_assignment(a, "modifiers." .. mid .. "." .. cid, errors, false)
                end
            end
        end
        local met = m.encoder_turn
        if met and met.kind == "actions" and (not is_command(met.cw) or not is_command(met.ccw)) then
            errors[#errors + 1] = "modifiers." .. mid .. ".encoder_turn: cw and ccw commands required"
        end
    end
    if modifier_count > 2 then errors[#errors + 1] = "at most two modifiers in total (ReaLearn conditions take two modifiers)" end
    M.validate_exquis(model.exquis, errors)
    if type(model.port1_input_device) ~= "number" then errors[#errors + 1] = "port1_input_device must be a number" end
    return errors
end

-- ---- persistence --------------------------------------------------------------------------------
local function this_dir()
    local src = debug.getinfo(1, "S").source:sub(2)
    return src:match("^(.*)[/\\]") or "."
end
M.DIR = this_dir()

function M.json()
    package.path = M.DIR .. "/?.lua;" .. package.path
    return require("json")
end

function M.load(path)
    local f = io.open(path, "r")
    if not f then return nil, "cannot open " .. path end
    local s = f:read("*a"); f:close()
    local ok, res = pcall(M.json().decode, s)
    if not ok then return nil, tostring(res) end
    return res
end

function M.save(model, path)
    local f, err = io.open(path, "w")
    if not f then return nil, err end
    f:write(M.json().encode(model, true), "\n"); f:close()
    return true
end

-- deep copy (tables only)
function M.copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = M.copy(x) end
    return t
end

return M

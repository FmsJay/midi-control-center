-- @description MIDI Control Center
-- @version 1.0
-- @author Oxygen Pro 61 integration
-- @about
--   ReaImGui editor for the Oxygen Pro 61 ReaLearn layout model. Draws the keyboard panel, lets you
--   click any control to edit what it does, and applies the generated preset to the running ReaLearn.
--   Needs ReaImGui 0.10 and the modules in ./midi_control_center (model, generator, apply, state, json).
-- @provides [main] .

-- ================================================================================================
-- 0. Guards, modules, ImGui context
-- ================================================================================================
if not reaper or not reaper.APIExists or not reaper.APIExists('ImGui_GetBuiltinPath') then
  reaper.MB('This script needs ReaImGui (install it via ReaPack).', 'MIDI Control Center', 0)
  return
end

local SCRIPT_PATH = debug.getinfo(1, 'S').source:sub(2)
local DIR = (SCRIPT_PATH:match('^(.*)[/\\]') or '.') .. '/midi_control_center'
package.path = DIR .. '/?.lua;' .. package.path .. ';' .. reaper.ImGui_GetBuiltinPath() .. '/?.lua'

local ImGui = require 'imgui' '0.10'
local M     = require 'model'
local apply = require 'apply'
local state = require 'state'

local ctx  = ImGui.CreateContext('MIDI Control Center')
local font = ImGui.CreateFont('sans-serif', ImGui.FontFlags_None)
ImGui.Attach(ctx, font)
local FLT_MIN = ImGui.NumericLimits_Float()

local EXT = 'MidiControlCenter'

-- toolbar toggle state
local _, _, section_id, cmd_id = reaper.get_action_context()
if cmd_id and cmd_id > 0 then
  reaper.SetToggleCommandState(section_id, cmd_id, 1)
  reaper.RefreshToolbar2(section_id, cmd_id)
end
reaper.atexit(function()
  if cmd_id and cmd_id > 0 then
    reaper.SetToggleCommandState(section_id, cmd_id, 0)
    reaper.RefreshToolbar2(section_id, cmd_id)
  end
end)

-- ================================================================================================
-- 1. Constants: colours, short names
-- ================================================================================================
local RGBA = {   -- pad LED colours as displayed
  off = 0x2A2C32FF, red = 0xFF3030FF, orange = 0xFF8C00FF, yellow = 0xFFE000FF, chartreuse = 0xA8FF20FF,
  green = 0x20E040FF, cyan = 0x20F0F0FF, aqua = 0x30D0FFFF, azure = 0x3090FFFF, blue = 0x3040FFFF,
  violet = 0x9040FFFF, magenta = 0xFF30FFFF, rose = 0xFF60A0FF, white = 0xF0F0F0FF,
}
local C = {
  bg = 0x1B1C20FF, line = 0x33353DFF, ink = 0xECEBE6FF, muted = 0x8F9098FF, btn = 0x2B2D35FF,
  btn_hover = 0x3A3D48FF, btn_static = 0x22232AFF, sel = 0xFFB000FF, live = 0x2F8CFFFF,
  track = 0x0C0D10FF, cap = 0x6A6D78FF, armed = 0xE6A6FFFF, err = 0xFF5050FF, ok = 0x60E080FF,
  knob = 0x3A3C44FF, keys = 0xE8E6E0FF, black = 0x101010FF, white = 0xF4F4F4FF, dim = 0x55575FFF,
}
local BUILTIN_SHORT = {
  none = '-', transport_play = 'Play/stop', transport_stop = 'Stop', transport_record = 'Record',
  transport_loop = 'Repeat', bank_prev = 'Bank -', bank_next = 'Bank +', padmode_prev = 'Pad mode -',
  padmode_next = 'Pad mode +', layout_toggle = 'Next layout', tap_tempo = 'Tap tempo',
}
local FB_MODES  = { 'Off', 'Record', 'Select', 'Mute', 'Solo' }                       -- fader-button mode (runtime)
local KNOB_FNS  = { 'Pan', 'Device (focused FX)', 'Send 1 per track', 'Selected track sends' } -- knob function (runtime)
local KNOB_SHORT = { 'Pan', 'FX', 'Send1', 'SelSnd' }

-- Exquis (optional second surface): display colours of the LED names, short assignment texts
local EXQUIS_RGBA = {}
for _, n in ipairs(M.EXQUIS_RGB) do EXQUIS_RGBA[n] = RGBA[n] or RGBA.off end
local EXQUIS_BUILTIN_SHORT = { transport_play = 'Play/stop', transport_record = 'Record', transport_loop = 'Repeat',
                               transport_stop = 'Stop', tap_tempo = 'Tap tempo', mode_next = 'Mode +', mode_prev = 'Mode -' }
local EXQUIS_ENCODER_SHORT = { none = '-', selected_volume = 'Sel vol', selected_pan = 'Sel pan', master_volume = 'Master vol',
                               selected_send = 'Sel send', browse_tracks = 'Browse trk', tempo = 'Tempo', fx_param = 'FX param',
                               zoom = 'Zoom', actions = 'Actions' }
local EXQUIS_PUSH_SHORT = { none = '-', selected_mute = 'Sel mute', selected_solo = 'Sel solo', selected_arm = 'Sel arm', tap_tempo = 'Tap tempo',
                            mode_next = 'Mode +', mode_prev = 'Mode -' }
local EXQUIS_ELEM = {}      -- button id -> element / CC number
for _, b in ipairs(M.EXQUIS_BUTTONS) do EXQUIS_ELEM[b.id] = b.elem end
local EXQUIS_ENC_CC, EXQUIS_PUSH_CC, EXQUIS_SLIDER_CC = { 110, 111, 112, 113 }, { 114, 115, 116, 117 }, { 80, 81, 82, 83, 84, 85 }
local DEVICES = { { id = 'oxygen', name = 'Oxygen Pro 61' }, { id = 'exquis', name = 'Exquis' } }
local EXQUIS_LAYERS = { { id = 'normal', name = 'Normal' }, { id = 'shift', name = 'Shift (FCB1010 held)' } }
local EXQUIS_HINT = 'off = no Exquis preset is written; needs the Exquis unit from the first-time setup and firmware 2.1+'

-- Exquis keyboard I/O: Developer-Mode sysex F0 00 21 7E 7F <cmd> ... F7 over the REAPER MIDI devices named "Exquis",
-- the .xqilayout files of the Exquis app, and the start-up snapshot file generator.lua embeds on Apply
local XQ = {}   -- one table for the constants and functions (the chunk is near Lua's 200-locals limit)
XQ.MFR  = string.char(0x00, 0x21, 0x7E, 0x7F)
XQ.HDR  = string.char(0xF0) .. XQ.MFR
XQ.CMD  = { snapshot = 0x09, root = 0x06, scale = 0x07 }
XQ.ROOTS  = { 'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B' }
XQ.SCALES = { 'Major', 'Natural Minor', 'Melodic Minor', 'Harmonic Minor', 'Dorian', 'Phrygian', 'Lydian', 'Mixolydian',
                    'Locrian', 'Phrygian dominant', 'Major Pentatonic', 'Minor Pentatonic', 'Whole Tone', 'Chromatic' }
XQ.ROOT_ITEMS, XQ.SCALE_ITEMS = {}, {}
for i, n in ipairs(XQ.ROOTS)  do XQ.ROOT_ITEMS[i]  = { id = i - 1, name = n } end
for i, n in ipairs(XQ.SCALES) do XQ.SCALE_ITEMS[i] = { id = i - 1, name = n } end
XQ.ROWS = { 6, 5, 6, 5, 6, 5, 6, 5, 6, 5, 6 }   -- keys per file row, bottom row of the upright keyboard first
XQ.LAYOUT_DIR = (os.getenv('USERPROFILE') or '') .. '/Documents/Intuitive Instruments/Exquis/Layouts'
XQ.SNAPSHOT_PATH = DIR .. '/exquis_snapshot.txt'
XQ.TIMEOUT = 3.0
XQ.KEY_OFF = 0x2A2B31FF

-- ================================================================================================
-- 2. State
-- ================================================================================================
local model, model_source = apply.load_model()
if type(model) == 'table' and type(model.exquis) == 'table' then M.exquis_migrate(model.exquis) end   -- flat Exquis -> modes[1]
local errors = M.validate(model)
local status = { text = 'Loaded ' .. tostring(model_source), col = nil }
local undo_stack, redo_stack = {}, {}
local UNDO_MAX = 60
local last_undo = { key = nil, t = 0 }
local sel  = { kind = nil }      -- button{id} | encoder | pad{k} | bank{sub,i} | layout | padmode
                                 -- Exquis: {dev='exquis', kind='button'|'encoder'|'push'|'slider', id=...}
local view = { layout = 1, mode = 1, bank = 1, layer = 'normal', follow = false, fb_mode = 0, knob_fn = 0,
               zoom = tonumber(reaper.GetExtState(EXT, 'zoom')) or 1.0,
               show_modifiers = false,    -- "Modifiers..." management section at the top of the inspector
               device = reaper.GetExtState(EXT, 'device') == 'exquis' and 'exquis' or 'oxygen',   -- Device switch
               xlayer = 'normal',         -- Exquis layer being edited: 'normal' | 'shift'
               xmode = 1,                 -- Exquis mode being edited: index into model.exquis.modes (1-based, clamped)
               show_xmode = false }       -- "Mode settings" section (name / colour) at the top of the Exquis inspector
local live = nil                 -- last state.read()
local picker = { active = false, uid = nil, resolver = nil, field = nil }
local last_error = nil
local pending_apply, apply_running = false, false
local last_action = nil
local pending_dock = tonumber(reaper.GetExtState(EXT, 'dock'))
if pending_dock == 0 then pending_dock = nil end
local name_cache = {}
local stk = { child = 0, combo = 0, col = 0, id = 0, disabled = 0 }   -- open Begin*/Push* for error recovery

-- Exquis keyboard I/O: live device settings, never part of the model (no undo). One query at a time, polled from
-- frame() each cycle: pending = 'snapshot' | 'root' | 'scale' | nil, queue = the queries still to send, done = callback.
local xq = {
  pending = nil, t0 = 0, last_seq = 0, queue = {}, done = nil,
  snapshot = nil,          -- 255 raw bytes (string) of the last cmd 09 reply, or of the snapshot file at start-up
  snapshot_src = nil,      -- 'keyboard' | 'file'
  keys = nil,              -- 61 x { note = n, col = RGBA } decoded from the snapshot
  root = nil, scale = nil, -- last values read from the device
  ui_root = 0, ui_scale = 0,   -- the Root / Scale combos
  layouts = nil,           -- parsed .xqilayout files (cached; "Rescan" reloads)
  layout = nil,            -- the file whose notes equal the snapshot's, or nil
  pick = nil,              -- file name chosen in the combo when nothing matched (display only)
  snap_file = nil,         -- { comment, bytes } of the snapshot file, or nil when absent
  out = nil, has_in = false, checked = -1, booted = false,
}

-- ================================================================================================
-- 3. Model helpers (undo, validation, lookups)
-- ================================================================================================
local function push_undo(key)
  local now = reaper.time_precise()
  if key and key == last_undo.key and now - last_undo.t < 1.0 then last_undo.t = now; return end
  undo_stack[#undo_stack + 1] = M.copy(model)
  if #undo_stack > UNDO_MAX then table.remove(undo_stack, 1) end
  redo_stack = {}
  last_undo.key, last_undo.t = key, now
end

-- drops "none" combos only; a modifier entry itself is never removed here (external hold modifiers
-- legitimately exist with empty combos, and button modifiers are removed by set_button_kind)
local function prune()
  for _, m in pairs(model.modifiers or {}) do
    for cid, a in pairs(m.combos or {}) do
      if type(a) == 'table' and a.kind == 'per_layout' then
        for lid, la in pairs(a.layouts or {}) do if la.kind == 'none' then a.layouts[lid] = nil end end
      elseif type(a) ~= 'table' or a.kind == 'none' or a.kind == nil then m.combos[cid] = nil end
    end
  end
end

local function after_edit(msg)
  prune()
  errors = M.validate(model)
  if msg then status.text, status.col = msg, nil end
end

local function undo()
  if #undo_stack == 0 then return end
  redo_stack[#redo_stack + 1] = model
  model = table.remove(undo_stack)
  last_undo.key = nil
  after_edit('Undo')
end
local function redo()
  if #redo_stack == 0 then return end
  undo_stack[#undo_stack + 1] = model
  model = table.remove(redo_stack)
  last_undo.key = nil
  after_edit('Redo')
end

local function set_table(t, new) for k in pairs(t) do t[k] = nil end; for k, v in pairs(new) do t[k] = v end end

local function layouts()  model.layouts = model.layouts or {}; return model.layouts end
local function banks()    model.banks = model.banks or {}; return model.banks end
local function buttons()  model.buttons = model.buttons or {}; return model.buttons end
local function cur_layout() return layouts()[view.layout] end
local function cur_modes()  local l = cur_layout(); if l then l.pad_modes = l.pad_modes or {}; return l.pad_modes end; return {} end
local function cur_mode()   return cur_modes()[view.mode] end
local function cur_bank()   return banks()[view.bank] end

-- every layer id: modifier buttons first (control order), then external hold modifiers (sorted)
local function modifier_ids() return M.modifier_ids(model) end
local function is_external(id) return M.is_external_modifier(model, id) end

-- human label of a layer id ('normal' | modifier button id | external modifier id)
local function layer_label(id)
  if id == 'normal' then return 'Normal' end
  local n = M.modifier_name(model, id)
  if is_external(id) then return n .. ' (hold)' end
  return n .. ' layer'
end

local function clamp_view()
  local n = #layouts(); if n == 0 then layouts()[1] = { id = 'layout1', name = 'Layout 1', sweep_colour = 'green', pad_modes = { { name = 'Free', kind = 'free', colour = 'white' } } } end
  view.layout = math.max(1, math.min(view.layout, #layouts()))
  view.mode   = math.max(1, math.min(view.mode, math.max(1, #cur_modes())))
  view.bank   = math.max(1, math.min(view.bank, math.max(1, #banks())))
  if view.layer ~= 'normal' then
    local found = false
    for _, id in ipairs(modifier_ids()) do if id == view.layer then found = true; break end end
    if not found then view.layer = 'normal' end
  end
  -- Exquis mode index (the section itself is only created on demand by exquis(), never here)
  local x = model.exquis
  if type(x) == 'table' and type(x.modes) == 'table' and #x.modes > 0 then
    view.xmode = math.max(1, math.min(math.floor(tonumber(view.xmode) or 1), #x.modes))
  end
end

local function ensure_button(id)
  local b = buttons()
  if type(b[id]) ~= 'table' then b[id] = { kind = 'none' } end
  return b[id]
end
local function ensure_modifier(mid)
  model.modifiers = model.modifiers or {}
  model.modifiers[mid] = model.modifiers[mid] or {}
  model.modifiers[mid].combos = model.modifiers[mid].combos or {}
  return model.modifiers[mid]
end

local function name_of(items, id)
  for _, it in ipairs(items) do if it.id == id then return it.name end end
  return tostring(id)
end

-- ---- Exquis section of the model (created on demand; every sub-table nil-safe) ----------------------
-- model.exquis = { enabled, shift_cc, shift_channel, port1_input_device, slider_mode, modes = { mode, ... } }; an old flat
-- section (buttons / encoders at the top level) is lifted into modes[1] here so every code path sees `modes`
local function exquis()
  if type(model.exquis) ~= 'table' then model.exquis = M.exquis_default() end
  local x = M.exquis_migrate(model.exquis)
  if type(x.modes) ~= 'table' or #x.modes == 0 then x.modes = { M.exquis_mode_track() } end
  view.xmode = math.max(1, math.min(math.floor(tonumber(view.xmode) or 1), #x.modes))
  return x
end
-- the Exquis mode being edited (model.exquis.modes[view.xmode]); a mode may lack shift / slider / pushes: created here
local function cur_xmode()
  local x = exquis()
  local m = x.modes[view.xmode]
  if type(m) ~= 'table' then m = { name = 'Mode ' .. view.xmode }; x.modes[view.xmode] = m end
  m.buttons  = m.buttons  or {}
  m.encoders = m.encoders or {}
  m.pushes   = m.pushes   or {}
  m.slider   = m.slider   or {}
  m.shift    = m.shift    or {}
  m.shift.buttons  = m.shift.buttons  or {}
  m.shift.encoders = m.shift.encoders or {}
  return m
end
-- button / encoder tables of an Exquis layer ('normal' | 'shift') in the mode being edited
local function xbuttons_of(layer)  local m = cur_xmode(); return layer == 'shift' and m.shift.buttons or m.buttons end
local function xencoders_of(layer) local m = cur_xmode(); return layer == 'shift' and m.shift.encoders or m.encoders end
local function xlayer_name(layer) return layer == 'shift' and 'Shift (FCB1010 held)' or 'Normal' end
local function xpath(layer, field) return 'model.exquis.modes[' .. view.xmode .. '].' .. (layer == 'shift' and 'shift.' or '') .. field end
-- a button builtin / push kind that steps through the Exquis modes on the device (its LED shows the mode colour)
local function is_mode_step(a)
  if type(a) ~= 'table' then return false end
  local k = a.kind == 'builtin' and a.builtin or a.kind
  return k == 'mode_next' or k == 'mode_prev'
end

-- ---- REAPER lookups ------------------------------------------------------------------------------
local function action_name(cmd)
  local id = cmd
  if type(cmd) == 'string' then id = reaper.NamedCommandLookup(cmd) end
  if type(id) ~= 'number' or id <= 0 then return '' end
  local key = tostring(cmd)
  if name_cache[key] then return name_cache[key] end
  local name = reaper.kbd_getTextFromCmd(math.floor(id), 0) or ''
  name_cache[key] = name
  return name
end

local function track_label(idx)
  if type(idx) ~= 'number' then return '?' end
  local tr = reaper.GetTrack(0, idx)
  if tr then
    local _, name = reaper.GetTrackName(tr)
    return string.format('%d "%s"', idx + 1, name)
  end
  return string.format('%d (no such track)', idx + 1)
end

-- ---- assignment text -----------------------------------------------------------------------------
local function command_text(cmd, long)
  if type(cmd) == 'string' then
    if long then local n = action_name(cmd); return cmd .. (n ~= '' and (' - ' .. n) or '') end
    return cmd:sub(2, 11)
  elseif type(cmd) == 'number' then
    if long then local n = action_name(cmd); return tostring(cmd) .. (n ~= '' and (' - ' .. n) or '') end
    return 'Action ' .. tostring(cmd)
  end
  return '(no command)'
end

local function resolve_per_layout(a)
  if type(a) == 'table' and a.kind == 'per_layout' then
    local l = cur_layout()
    return (a.layouts or {})[l and l.id] or { kind = 'none' }
  end
  return a
end

local function assignment_text(a, long)
  a = resolve_per_layout(a)
  if type(a) ~= 'table' or a.kind == nil or a.kind == 'none' then return '-' end
  if a.kind == 'builtin' then return long and name_of(M.BUILTINS, a.builtin) or (BUILTIN_SHORT[a.builtin] or tostring(a.builtin)) end
  if a.kind == 'action' then return command_text(a.command, long) end
  if a.kind == 'modifier' then return 'Modifier (latch)' end
  return '?'
end

-- what button `id` does in the selected layer
local function layer_assignment(id)
  if view.layer == 'normal' then return (model.buttons or {})[id] end
  if id == view.layer and not is_external(view.layer) then return { kind = 'modifier' } end
  local m = (model.modifiers or {})[view.layer]
  return m and m.combos and m.combos[id]
end

local function layer_encoder()
  if view.layer == 'normal' then return model.encoder_turn end
  local m = (model.modifiers or {})[view.layer]
  return m and m.encoder_turn
end

local function encoder_text(e, long)
  if type(e) ~= 'table' or e.kind == nil or e.kind == 'none' then return '-' end
  if e.kind == 'actions' then
    if long then return 'CW ' .. command_text(e.cw, true) .. ' / CCW ' .. command_text(e.ccw, true) end
    return 'CW ' .. command_text(e.cw) .. ' / CCW ' .. command_text(e.ccw)
  end
  if long then return name_of(M.ENCODER_KINDS, e.kind) end
  return e.kind == 'browse_tracks' and 'Browse tracks' or 'Zoom'
end

-- ---- Exquis assignment text + colours -------------------------------------------------------------
local function xbutton_text(a, long)
  if type(a) ~= 'table' or a.kind == nil or a.kind == 'none' then return '-' end
  if a.kind == 'builtin' then return long and name_of(M.EXQUIS_BUTTON_BUILTINS, a.builtin) or (EXQUIS_BUILTIN_SHORT[a.builtin] or tostring(a.builtin)) end
  if a.kind == 'action' then return command_text(a.command, long) end
  return '?'
end
local function xencoder_text(a, long)
  if type(a) ~= 'table' or a.kind == nil or a.kind == 'none' then return '-' end
  if a.kind == 'actions' then
    if long then return 'CW ' .. command_text(a.cw, true) .. ' / CCW ' .. command_text(a.ccw, true) end
    return 'CW ' .. command_text(a.cw) .. ' / CCW ' .. command_text(a.ccw)
  end
  local n = math.floor(tonumber(a.index) or 0) + 1
  if a.kind == 'selected_send' then return (long and 'Selected track send ' or 'Sel send ') .. n end
  if a.kind == 'fx_param' then return (long and 'Focused FX parameter ' or 'FX param ') .. n end
  if long then return name_of(M.EXQUIS_ENCODER_KINDS, a.kind) end
  return EXQUIS_ENCODER_SHORT[a.kind] or tostring(a.kind)
end
-- encoder pushes and slider zones share the shape {kind, command | action}
local function xpush_text(a, long, kinds)
  if type(a) ~= 'table' or a.kind == nil or a.kind == 'none' then return '-' end
  if a.kind == 'action' then return command_text(a.command, long) end
  if a.kind == 'transport' then return (long and 'Transport ' or '') .. tostring(a.action or 'PlayStop') end
  if long then return name_of(kinds or M.EXQUIS_PUSH_KINDS, a.kind) end
  return EXQUIS_PUSH_SHORT[a.kind] or tostring(a.kind)
end

local function half_rgba(rgba)
  local r = ((rgba >> 24) & 0xFF) // 2; local g = ((rgba >> 16) & 0xFF) // 2; local b = ((rgba >> 8) & 0xFF) // 2
  return (r << 24) | (g << 16) | (b << 8) | 0xFF
end
-- display colour of an Exquis assignment: LED name -> RGBA, halved when dim; nil colour = off. `mode_col` (RGBA) is
-- what a mode_next / mode_prev assignment without its own colour shows: the mode's colour, as the interpreter paints it
local function xcolour(a, mode_col)
  if mode_col and is_mode_step(a) and not a.colour then return a.dim and half_rgba(mode_col) or mode_col end
  local col = (type(a) == 'table' and a.colour and EXQUIS_RGBA[a.colour]) or RGBA.off
  if type(a) == 'table' and a.dim then col = half_rgba(col) end
  return col
end
local function has_colour(a)
  if type(a) ~= 'table' then return false end
  if a.colour == nil then return is_mode_step(a) end   -- mode steps are lit in the mode colour
  return a.colour ~= 'off'
end

-- fader / knob / fader-button meaning for a bank
local function fader_text(b, i)
  if i == 9 then return 'Master' end
  if not b then return '-' end
  if b.kind == 'tracks' then return 'Vol T' .. ((b.first_track or 0) + i) end
  if b.kind == 'focused_fx' then return 'FX p' .. i end
  return '-'
end
local function knob_text(b, i, fn)
  if not b then return '-' end
  if b.kind == 'tracks' then
    local t = (b.first_track or 0) + i
    if fn == 0 then return 'Pan T' .. t elseif fn == 1 then return 'FX p' .. i
    elseif fn == 2 then return 'Send1 T' .. t else return 'Sel snd ' .. i end
  end
  if b.kind == 'focused_fx' then return 'FX p' .. (i + 8) end
  return '-'
end
local function fbtn_text(b, i, mode)
  if not b or mode == 0 then return '-' end
  if b.kind == 'tracks' then
    local t = (b.first_track or 0) + i
    return ({ 'Arm T', 'Sel T', 'Mute T', 'Solo T' })[mode] .. t
  end
  if b.kind == 'focused_fx' then
    if mode == 2 then return 'FX ' .. i .. ' on/off' end
    if mode == 3 then return ({ 'Sel mute', 'Sel solo', 'Sel arm', 'Sel FX byp' })[i] or '-' end
  end
  return '-'
end

-- pad k in the current layout + pad mode: fill colour, short text, long text
local function pad_info(k)
  local pm = cur_mode()
  if not pm then return RGBA.off, '-', 'no pad mode' end
  if pm.kind == 'drums' then
    return RGBA.blue, 'Drum ' .. k, 'Drum hit -> port 1 ch 10 (velocity colours)'
  elseif pm.kind == 'mixer' then
    local ft = pm.first_track or 0
    if k <= 8 then return RGBA.chartreuse, 'Mute T' .. (ft + k), 'Mute track ' .. track_label(ft + k - 1) end
    return RGBA.azure, 'Solo T' .. (ft + k - 8), 'Solo track ' .. track_label(ft + k - 9)
  elseif pm.kind == 'free' then
    return RGBA[pm.colour or 'white'] or RGBA.off, '-', 'Free pad (nothing mapped)'
  end
  local p = (pm.pads or {})[k]
  if not p or p.kind == nil or p.kind == 'none' then
    return RGBA[(p and p.colour) or 'off'] or RGBA.off, '-', 'Nothing (just a colour)'
  elseif p.kind == 'action' then
    return RGBA[p.colour or 'off'] or RGBA.off, command_text(p.command), 'Action ' .. command_text(p.command, true)
  elseif p.kind == 'transport' then
    return RGBA[p.colour or 'azure'] or RGBA.off, tostring(p.action), 'Transport ' .. tostring(p.action)
  elseif p.kind == 'track_state' then
    local t = (p.track or 0)
    return RGBA[p.colour or 'chartreuse'] or RGBA.off, tostring(p.state) .. ' T' .. (t + 1), tostring(p.state) .. ' track ' .. track_label(t)
  end
  return RGBA.off, '?', 'unknown pad kind ' .. tostring(p.kind)
end

local function ink_for(rgba)
  local r = (rgba >> 24) & 0xFF; local g = (rgba >> 16) & 0xFF; local b = (rgba >> 8) & 0xFF
  return (0.299 * r + 0.587 * g + 0.114 * b) > 140 and C.black or C.white
end

-- ================================================================================================
-- 4. Action picker (REAPER's own Actions window in pick mode)
-- ================================================================================================
local pending_picker = nil
local function picker_start(uid, resolver, field)
  -- opening REAPER's Actions window pumps messages; do it between frames, not inside one
  pending_picker = { uid = uid, resolver = resolver, field = field }
end
local function picker_open_now()
  local pk = pending_picker; pending_picker = nil
  if picker.active then reaper.PromptForAction(-1, 0, 0) end
  reaper.PromptForAction(1, 0, 0)
  picker.active, picker.uid, picker.resolver, picker.field = true, pk.uid, pk.resolver, pk.field
end

local function picker_poll()
  if not picker.active then return end
  local r = reaper.PromptForAction(0, 0, 0)
  if r > 0 then
    reaper.PromptForAction(-1, 0, 0)
    picker.active = false
    local named = reaper.ReverseNamedCommandLookup(r)
    local value = (type(named) == 'string' and named ~= '') and ('_' .. named) or math.floor(r)
    local t = picker.resolver and picker.resolver()
    if type(t) == 'table' then
      push_undo()
      t[picker.field] = value
      after_edit('Picked ' .. command_text(value, true))
    end
  elseif r < 0 then
    picker.active = false
    status.text = 'Action picker closed'
  end
end

-- ================================================================================================
-- 5. ImGui helpers (balanced Begin/End tracking, combos, widgets)
-- ================================================================================================
local function begin_child(id, w, h, cflags, wflags)
  local vis = ImGui.BeginChild(ctx, id, w or 0, h or 0, cflags or ImGui.ChildFlags_None, wflags or ImGui.WindowFlags_None)
  if vis then stk.child = stk.child + 1 end
  return vis
end
local function end_child() ImGui.EndChild(ctx); stk.child = stk.child - 1 end
local function push_id(s) ImGui.PushID(ctx, s); stk.id = stk.id + 1 end
local function pop_id() ImGui.PopID(ctx); stk.id = stk.id - 1 end
local function push_col(idx, col) ImGui.PushStyleColor(ctx, idx, col); stk.col = stk.col + 1 end
local function pop_col(n) n = n or 1; ImGui.PopStyleColor(ctx, n); stk.col = stk.col - n end
local function push_wrap() ImGui.PushTextWrapPos(ctx, 0.0); stk.wrap = (stk.wrap or 0) + 1 end
local function pop_wrap() ImGui.PopTextWrapPos(ctx); stk.wrap = stk.wrap - 1 end
local function begin_disabled(d) ImGui.BeginDisabled(ctx, d); stk.disabled = stk.disabled + 1 end
local function end_disabled() ImGui.EndDisabled(ctx); stk.disabled = stk.disabled - 1 end

-- after a pcall failure inside the frame, close whatever is still open so the next frame is clean
local function unwind()
  while (stk.wrap or 0) > 0 do ImGui.PopTextWrapPos(ctx); stk.wrap = stk.wrap - 1 end
  while stk.combo > 0 do ImGui.EndCombo(ctx); stk.combo = stk.combo - 1 end
  while stk.disabled > 0 do ImGui.EndDisabled(ctx); stk.disabled = stk.disabled - 1 end
  while stk.id > 0 do ImGui.PopID(ctx); stk.id = stk.id - 1 end
  if stk.col > 0 then ImGui.PopStyleColor(ctx, stk.col); stk.col = 0 end
  while stk.child > 0 do ImGui.EndChild(ctx); stk.child = stk.child - 1 end
end

-- combo over {id,name} items; returns the newly chosen id or nil
-- a fixed combo width is only a minimum: grow it so the longest entry (and the arrow) fits, up to the space left
local function fit_combo_width(width, texts)
  if not width or width <= 0 then return width end
  local widest = 0
  for _, t in ipairs(texts) do
    local w = ImGui.CalcTextSize(ctx, tostring(t))
    if w > widest then widest = w end
  end
  local avail = ImGui.GetContentRegionAvail(ctx)
  return math.max(width, math.min(widest + 44, avail))
end
local function combo_ids(label, items, cur, width)
  if width then
    local names = {}
    for i, it in ipairs(items) do names[i] = it.name end
    ImGui.SetNextItemWidth(ctx, fit_combo_width(width, names))
  end
  local chosen
  if ImGui.BeginCombo(ctx, label, name_of(items, cur)) then
    stk.combo = stk.combo + 1
    for _, it in ipairs(items) do
      if ImGui.Selectable(ctx, it.name, it.id == cur) then chosen = it.id end
      if it.id == cur then ImGui.SetItemDefaultFocus(ctx) end
    end
    ImGui.EndCombo(ctx); stk.combo = stk.combo - 1
  end
  return chosen
end

-- combo over plain strings; returns the newly chosen string or nil
local function combo_strings(label, list, cur, width)
  if width then ImGui.SetNextItemWidth(ctx, fit_combo_width(width, list)) end
  local chosen
  if ImGui.BeginCombo(ctx, label, tostring(cur or '-')) then
    stk.combo = stk.combo + 1
    for _, s in ipairs(list) do
      if ImGui.Selectable(ctx, s, s == cur) then chosen = s end
    end
    ImGui.EndCombo(ctx); stk.combo = stk.combo - 1
  end
  return chosen
end

local function swatch(col, size)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(dl, x, y + 2, x + size, y + 2 + size, col, 3)
  ImGui.DrawList_AddRect(dl, x, y + 2, x + size, y + 2 + size, C.line, 3)
  ImGui.Dummy(ctx, size, size)
end

-- colour combo with swatches. `cur` may be nil when allow_default; returns changed, new value (false = no change)
local function colour_combo(label, cur, allow_default, width)
  swatch(RGBA[cur or 'off'] or RGBA.off, 16); ImGui.SameLine(ctx)
  if width then ImGui.SetNextItemWidth(ctx, width) end
  local changed, value = false, nil
  if ImGui.BeginCombo(ctx, label, cur or '(default)') then
    stk.combo = stk.combo + 1
    if allow_default then
      if ImGui.Selectable(ctx, '(default)', cur == nil) then changed, value = true, nil end
    end
    for _, name in ipairs(M.COLOUR_ORDER) do
      push_id(name)
      swatch(RGBA[name], 14); ImGui.SameLine(ctx)
      if ImGui.Selectable(ctx, name, name == cur) then changed, value = true, name end
      pop_id()
    end
    ImGui.EndCombo(ctx); stk.combo = stk.combo - 1
  end
  return changed, value
end

-- Exquis LED colour combo (names from M.EXQUIS_RGB, '(none)' = nil); returns changed, new value
local function exquis_colour_combo(label, cur, width)
  swatch(EXQUIS_RGBA[cur or 'off'] or RGBA.off, 16); ImGui.SameLine(ctx)
  if width then ImGui.SetNextItemWidth(ctx, width) end
  local changed, value = false, nil
  if ImGui.BeginCombo(ctx, label, cur or '(none)') then
    stk.combo = stk.combo + 1
    if ImGui.Selectable(ctx, '(none)', cur == nil) then changed, value = true, nil end
    for _, name in ipairs(M.EXQUIS_RGB) do
      push_id(name)
      swatch(EXQUIS_RGBA[name], 14); ImGui.SameLine(ctx)
      if ImGui.Selectable(ctx, name, name == cur) then changed, value = true, name end
      pop_id()
    end
    ImGui.EndCombo(ctx); stk.combo = stk.combo - 1
  end
  return changed, value
end

-- command editor: integer id, "Pick action..." button, named command text, action name
local function command_widget(uid, resolver, field)
  local t = resolver()
  if type(t) ~= 'table' then return end
  push_id(uid)
  local v = t[field]
  local num = type(v) == 'number' and math.floor(v) or 0
  local named = type(v) == 'string' and v or ''
  ImGui.SetNextItemWidth(ctx, 90)
  local rv, nv = ImGui.InputInt(ctx, '##num', num, 0, 0)
  if rv and nv ~= num then push_undo('cmd' .. uid); t[field] = nv; after_edit() end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Pick action...') then picker_start(uid, resolver, field) end
  if picker.active and picker.uid == uid then
    ImGui.SameLine(ctx); ImGui.TextColored(ctx, C.live, 'waiting for the Actions window...')
  end
  ImGui.SetNextItemWidth(ctx, -FLT_MIN)
  local rv2, ns = ImGui.InputTextWithHint(ctx, '##named', '_NAMED_COMMAND (leave empty to use the number)', named)
  if rv2 and ns ~= named then
    push_undo('named' .. uid)
    if ns ~= '' then t[field] = ns else t[field] = num end
    after_edit()
  end
  local name = action_name(t[field])
  if name ~= '' then ImGui.TextDisabled(ctx, name)
  elseif t[field] ~= nil and t[field] ~= 0 and t[field] ~= '' then ImGui.TextColored(ctx, C.err, 'unknown action') end
  pop_id()
end

local function track_widget(uid, t, field)
  push_id(uid)
  ImGui.SetNextItemWidth(ctx, 90)
  local cur = math.floor(tonumber(t[field]) or 0)
  local rv, nv = ImGui.InputInt(ctx, '##track', cur, 1, 8)
  if rv and nv ~= cur then push_undo('trk' .. uid); t[field] = math.max(0, nv); after_edit() end
  ImGui.SameLine(ctx); ImGui.TextDisabled(ctx, 'track ' .. track_label(t[field] or 0))
  pop_id()
end

local function text_field(uid, label, t, field, width)
  push_id(uid)
  if width then ImGui.SetNextItemWidth(ctx, width) end
  local cur = tostring(t[field] or '')
  local rv, nv = ImGui.InputText(ctx, label, cur)
  if rv and nv ~= cur then push_undo('txt' .. uid); t[field] = nv; after_edit() end
  pop_id()
end

-- ================================================================================================
-- 6. Structural edits: layouts, pad modes, banks
-- ================================================================================================
local function unique_layout_id(base)
  local used = {}
  for _, l in ipairs(layouts()) do used[l.id] = true end
  local n = 1
  while used[base .. n] do n = n + 1 end
  return base .. n
end

local function add_layout()
  push_undo()
  local src = cur_layout()
  local new = src and M.copy(src) or { pad_modes = {} }
  new.id = unique_layout_id('layout')
  new.name = (src and src.name or 'Layout') .. ' copy'
  layouts()[#layouts() + 1] = new
  view.layout = #layouts()
  after_edit('Added layout ' .. new.name)
end

local function delete_layout()
  if #layouts() <= 1 then status.text, status.col = 'Cannot delete the last layout', C.err; return end
  push_undo()
  local l = table.remove(layouts(), view.layout)
  for _, m in pairs(model.modifiers or {}) do
    for _, a in pairs(m.combos or {}) do
      if type(a) == 'table' and a.kind == 'per_layout' and a.layouts then a.layouts[l.id] = nil end
    end
  end
  after_edit('Deleted layout ' .. tostring(l.name))
end

local function rename_layout_id(old, new)
  if new == '' or new == old then return end
  for _, l in ipairs(layouts()) do if l.id == new then status.text, status.col = 'Layout id already used', C.err; return end end
  push_undo()
  cur_layout().id = new
  for _, m in pairs(model.modifiers or {}) do
    for _, a in pairs(m.combos or {}) do
      if type(a) == 'table' and a.kind == 'per_layout' and a.layouts and a.layouts[old] then
        a.layouts[new] = a.layouts[old]; a.layouts[old] = nil
      end
    end
  end
  after_edit('Renamed layout id')
end

local function add_pad_mode()
  push_undo()
  local n = #cur_modes() + 1
  for _, l in ipairs(layouts()) do
    l.pad_modes = l.pad_modes or {}
    l.pad_modes[#l.pad_modes + 1] = { name = 'Mode ' .. n, kind = 'free', colour = 'white' }
  end
  view.mode = #cur_modes()
  after_edit('Added pad mode in every layout')
end

local function remove_pad_mode()
  if #cur_modes() <= 1 then status.text, status.col = 'Cannot remove the last pad mode', C.err; return end
  push_undo()
  for _, l in ipairs(layouts()) do
    if l.pad_modes and #l.pad_modes >= view.mode then table.remove(l.pad_modes, view.mode) end
  end
  after_edit('Removed pad mode from every layout')
end

local function set_pad_mode_kind(pm, kind)
  pm.kind = kind
  if kind == 'mixer' then pm.first_track = pm.first_track or 0
  elseif kind == 'free' then pm.colour = pm.colour or 'white'
  elseif kind == 'custom' then pm.pads = pm.pads or {} end
end

local function add_bank()
  if #banks() >= 8 then status.text, status.col = 'At most 8 fader banks', C.err; return end
  push_undo()
  banks()[#banks() + 1] = { name = 'Bank ' .. (#banks() + 1), kind = 'free' }
  view.bank = #banks()
  after_edit('Added bank')
end
local function remove_bank()
  if #banks() <= 1 then status.text, status.col = 'At least one bank is required', C.err; return end
  push_undo()
  table.remove(banks(), view.bank)
  after_edit('Removed bank')
end

-- Exquis modes (model.exquis.modes, 1..8): "+" copies the mode being edited, "-" removes it (never below one)
local function add_xmode()
  local x = exquis()
  if #x.modes >= 8 then status.text, status.col = 'At most 8 Exquis modes', C.err; return end
  push_undo()
  local new = M.copy(cur_xmode())
  new.name = 'Mode ' .. (#x.modes + 1)
  x.modes[#x.modes + 1] = new
  view.xmode = #x.modes
  after_edit('Added Exquis mode ' .. new.name .. ' (copy of the current mode)')
end
local function remove_xmode()
  local x = exquis()
  if #x.modes <= 1 then status.text, status.col = 'At least one Exquis mode is required', C.err; return end
  push_undo()
  local m = table.remove(x.modes, view.xmode)
  view.xmode = math.max(1, math.min(view.xmode, #x.modes))
  after_edit('Removed Exquis mode ' .. tostring(m and m.name or '?'))
end

-- kind change of a button assignment (normal layer allows modifier)
local function set_button_kind(a, kind, id)
  if kind == 'none' then set_table(a, { kind = 'none' })
  elseif kind == 'builtin' then set_table(a, { kind = 'builtin', builtin = 'transport_play' })
  elseif kind == 'action' then set_table(a, { kind = 'action', command = 0 })
  elseif kind == 'modifier' then set_table(a, { kind = 'modifier', indicator = 'checkerboard' }); ensure_modifier(id) end
  -- a button that stops being a modifier loses its layer; external hold modifiers are never touched here
  if kind ~= 'modifier' and id and model.modifiers and not is_external(id) then
    model.modifiers[id] = nil
    if view.layer == id then view.layer = 'normal' end
  end
end

-- ================================================================================================
-- 6b. Exquis keyboard I/O: layout files, snapshot file, Developer-Mode queries (non-blocking)
-- ================================================================================================
function XQ.note_name(n)
  n = math.floor(tonumber(n) or 0)
  return XQ.ROOTS[n % 12 + 1] .. tostring(n // 12 - 1)
end

-- .xqilayout colour "AARRGGBB" (or "0" = unlit) -> RGBA
function XQ.file_colour(c)
  local v = tonumber(c, 16) or 0
  if (v & 0xFFFFFF) == 0 then return XQ.KEY_OFF end
  return ((v & 0xFFFFFF) << 8) | 0xFF
end

-- snapshot record r, g, b (0-127 each) -> RGBA
function XQ.snapshot_colour(r, g, b)
  if r == 0 and g == 0 and b == 0 then return XQ.KEY_OFF end
  local function s(v) return math.min(255, math.floor(v * 255 / 127 + 0.5)) end
  return (s(r) << 24) | (s(g) << 16) | (s(b) << 8) | 0xFF
end

function XQ.output()
  for i = 0, reaper.GetNumMIDIOutputs() - 1 do
    local ok, n = reaper.GetMIDIOutputNameNoAlias(i, '')
    if ok and n == 'Exquis' then return i end
  end
  return nil
end
function XQ.input_present()
  for i = 0, reaper.GetNumMIDIInputs() - 1 do
    local ok, n = reaper.GetMIDIInputNameNoAlias(i, '')
    if ok and n == 'Exquis' then return true end
  end
  return false
end

-- sends F0 00 21 7E 7F <bytes...> F7; false (with a status message) when no Exquis output exists
function XQ.send(bytes)
  local out = XQ.output()
  xq.out = out
  if not out then
    status.text, status.col = 'No MIDI output named "Exquis" (enable it in Preferences > MIDI Devices)', C.err
    return false
  end
  local s = XQ.HDR .. string.char(table.unpack(bytes)) .. string.char(0xF7)
  reaper.SendMIDIMessageToHardware(out, s, #s)
  return true
end

-- ---- layout files ---------------------------------------------------------------------------------
function XQ.scan_layouts()
  local list, i = {}, 0
  while true do
    local fn = reaper.EnumerateFiles(XQ.LAYOUT_DIR, i)
    if not fn then break end
    if fn:lower():sub(-10) == '.xqilayout' then
      local f = io.open(XQ.LAYOUT_DIR .. '/' .. fn, 'rb')
      if f then
        local s = f:read('*a'); f:close()
        local notes, cols = {}, {}
        for n, c in s:gmatch('noteNumber="(%d+)"%s+colour="(%x+)"') do
          notes[#notes + 1] = math.floor(tonumber(n) or 0); cols[#cols + 1] = XQ.file_colour(c)
        end
        -- the file name is the identity: the name="..." attribute inside is often inherited from the layout a file
        -- was duplicated from, so it is kept only as a secondary title
        if #notes == 61 then
          list[#list + 1] = { file = fn, name = (fn:gsub('%.[Xx][Qq][Ii][Ll][Aa][Yy][Oo][Uu][Tt]$', '')),
                              title = s:match('<LAYOUT[^>]-name="([^"]*)"'), notes = notes, colours = cols }
        end
      end
    end
    i = i + 1
  end
  table.sort(list, function(a, b) return a.file:lower() < b.file:lower() end)
  xq.layouts = list
  return list
end

function XQ.layout_by_file(file)
  for _, l in ipairs(xq.layouts or {}) do if l.file == file then return l end end
  return nil
end

-- decode the 255 snapshot bytes (11 header bytes, then 61 x note r g b) into xq.keys, then find the file whose
-- 61 note numbers equal the snapshot's in order
function XQ.identify()
  xq.keys, xq.layout = nil, nil
  local snap = xq.snapshot
  if not snap or #snap < 11 + 61 * 4 then return end
  local keys = {}
  for k = 1, 61 do
    local o = 12 + 4 * (k - 1)
    keys[k] = { note = snap:byte(o), col = XQ.snapshot_colour(snap:byte(o + 1), snap:byte(o + 2), snap:byte(o + 3)) }
  end
  xq.keys, xq.also = keys, {}
  if not xq.layouts then XQ.scan_layouts() end
  for _, l in ipairs(xq.layouts) do
    local same = true
    for k = 1, 61 do if l.notes[k] ~= keys[k].note then same = false; break end end
    if same then
      if xq.layout then xq.also[#xq.also + 1] = l.name    -- duplicates with the same 61 notes (file copies)
      else xq.layout = l; xq.pick = nil end
    end
  end
end

-- ---- snapshot file (midi_control_center/exquis_snapshot.txt: "# comment" line, then the bytes as hex) ----
function XQ.read_snapshot_file()
  local f = io.open(XQ.SNAPSHOT_PATH, 'rb')
  if not f then return nil end
  local s = f:read('*a'); f:close()
  local bytes = {}
  for line in s:gmatch('[^\r\n]+') do
    if line:sub(1, 1) ~= '#' then for h in line:gmatch('%x%x') do bytes[#bytes + 1] = string.char(tonumber(h, 16)) end end
  end
  return { comment = s:match('^#%s*([^\r\n]*)') or '', bytes = #bytes, raw = table.concat(bytes) }
end

function XQ.write_snapshot_file()
  if not xq.snapshot then status.text, status.col = 'No snapshot to write', C.err; return end
  local hex = {}
  for b = 1, #xq.snapshot do hex[#hex + 1] = string.format('%02X', xq.snapshot:byte(b)) end
  local f, err = io.open(XQ.SNAPSHOT_PATH, 'w')
  if not f then status.text, status.col = 'Cannot write ' .. XQ.SNAPSHOT_PATH .. ': ' .. tostring(err), C.err; return end
  f:write('# Exquis snapshot captured ' .. os.date('%Y-%m-%d %H:%M') .. ' (' .. #xq.snapshot .. ' bytes)\n' .. table.concat(hex, ' ') .. '\n')
  f:close()
  xq.checked = -1
  status.text, status.col = string.format('snapshot: captured %s, %d bytes -> %s (embedded on the next Apply)', os.date('%H:%M:%S'), #xq.snapshot, XQ.SNAPSHOT_PATH), C.ok
end

-- send the stored (or last read) snapshot back to the keyboard right now, without an Apply
function XQ.restore_snapshot()
  local raw = (xq.snap_file and xq.snap_file.bytes == 255 and xq.snap_file.raw) or xq.snapshot
  if not raw or #raw ~= 255 then status.text, status.col = 'No 255-byte snapshot to restore (read or capture one first)', C.err; return end
  local mask = (model.exquis and model.exquis.slider_mode == 'zones') and 0x2E or 0x2A
  if not XQ.send({ 0x00, mask }) then return end
  local bytes = { 0x09 }
  for b = 1, #raw do bytes[#bytes + 1] = raw:byte(b) end
  XQ.send(bytes)
  status.text, status.col = 'Snapshot sent to the keyboard (layout + MIDI settings restored)', C.ok
end

function XQ.clear_snapshot_file()
  local ok, err = os.remove(XQ.SNAPSHOT_PATH)
  xq.checked = -1
  if ok then status.text, status.col = 'Snapshot file deleted; the Exquis keeps its own layout from the next Apply on', nil
  else status.text, status.col = 'Cannot delete the snapshot file: ' .. tostring(err), C.err end
end

-- once a second: device presence and the snapshot file; at start-up the file (if any) seeds the key field
function XQ.refresh()
  local now = reaper.time_precise()
  if now - xq.checked < 1.0 then return end
  xq.checked = now
  xq.out = XQ.output()
  xq.has_in = XQ.input_present()
  xq.snap_file = XQ.read_snapshot_file()
  if not xq.booted then
    xq.booted = true
    if xq.snap_file and xq.snap_file.bytes == 255 then
      xq.snapshot, xq.snapshot_src = xq.snap_file.raw, 'file'
      XQ.identify()
    end
  end
end

-- ---- query state machine --------------------------------------------------------------------------
function XQ.stop(msg, col)
  xq.pending, xq.queue, xq.done = nil, {}, nil
  if msg then status.text, status.col = msg, col end
end

-- send the next queued query; nothing left = run the completion callback
function XQ.next()
  local kind = table.remove(xq.queue, 1)
  if not kind then
    local done = xq.done
    xq.pending, xq.done = nil, nil
    if done then done() end
    return
  end
  if not XQ.send({ XQ.CMD[kind] }) then XQ.stop(); return end
  xq.pending, xq.t0 = kind, reaper.time_precise()
  local seq = reaper.MIDI_GetRecentInputEvent(0)   -- only events newer than this one are replies
  xq.last_seq = seq or 0
end

function XQ.start(kinds, done)
  if xq.pending then status.text, status.col = 'Exquis: still waiting for the ' .. xq.pending .. ' reply', C.err; return end
  if not XQ.send({ 0x00, 0x2E }) then return end   -- Developer Mode on (harmless to repeat)
  if not XQ.input_present() then status.text, status.col = 'No MIDI input named "Exquis": the reply cannot arrive', C.err
  else status.text, status.col = 'Exquis: querying...', C.live end
  xq.queue = {}
  for _, k in ipairs(kinds) do xq.queue[#xq.queue + 1] = k end
  xq.done = done
  XQ.next()
end

function XQ.handle(kind, body)
  if kind == 'snapshot' then
    xq.snapshot, xq.snapshot_src = body, 'keyboard'
    XQ.identify()
  elseif kind == 'root' then
    local v = body:byte(1)
    if v and v <= 11 then xq.root, xq.ui_root = v, v end
  elseif kind == 'scale' then
    local v = body:byte(1)
    if v and v <= #XQ.SCALES - 1 then xq.scale, xq.ui_scale = v, v end
  end
end

-- called every frame: looks for the pending reply among the new input events (newest first), or times out
function XQ.poll()
  if not xq.pending then return end
  local want = XQ.MFR .. string.char(XQ.CMD[xq.pending])
  local newest, got
  for i = 0, 255 do
    local seq, buf = reaper.MIDI_GetRecentInputEvent(i)
    if not seq or seq == 0 or seq <= xq.last_seq then break end
    if newest == nil then newest = seq end
    if not got and type(buf) == 'string' and #buf >= 7 and buf:byte(1) == 0xF0 and buf:sub(2, 6) == want then
      got = buf:sub(7)
      if got:byte(-1) == 0xF7 then got = got:sub(1, -2) end
    end
  end
  if newest then xq.last_seq = newest end
  if got then
    local kind = xq.pending
    XQ.handle(kind, got)
    XQ.next()
  elseif reaper.time_precise() - xq.t0 > XQ.TIMEOUT then
    XQ.stop('Exquis: no ' .. xq.pending .. ' reply within 3 s (input "Exquis" enabled? firmware with Developer Mode?)', C.err)
  end
end

-- ---- user actions ---------------------------------------------------------------------------------
function XQ.read_from_keyboard()
  XQ.start({ 'snapshot', 'root', 'scale' }, function()
    status.text, status.col = string.format('Exquis read: layout %s, root %s, scale %s',
      xq.layout and xq.layout.name or 'unknown', XQ.ROOTS[(xq.root or 0) + 1], XQ.SCALES[(xq.scale or 0) + 1]), C.ok
  end)
end
function XQ.capture_snapshot()
  XQ.start({ 'snapshot' }, XQ.write_snapshot_file)
end
function XQ.send_root_scale()
  if xq.pending then status.text, status.col = 'Exquis: wait for the pending query first', C.err; return end
  if XQ.send({ 0x00, 0x2E }) and XQ.send({ 0x06, xq.ui_root }) and XQ.send({ 0x07, xq.ui_scale }) then
    xq.root, xq.scale = xq.ui_root, xq.ui_scale
    status.text, status.col = 'Sent to the Exquis: root ' .. XQ.ROOTS[xq.ui_root + 1] .. ', scale ' .. XQ.SCALES[xq.ui_scale + 1], C.ok
  end
end

-- what the key field shows: the snapshot's own keys, else the file picked in the combo, else nothing
function XQ.display()
  if xq.keys then
    local l = xq.layout
    local name = l and l.name or 'unknown layout'
    local note = l and (xq.snapshot_src == 'file' and 'from the snapshot file' or 'confirmed by the keyboard')
                   or 'no layout file has these notes'
    if l and xq.also and #xq.also > 0 then note = note .. '; same notes in: ' .. table.concat(xq.also, ', ') end
    return xq.keys, 'Layout: ' .. name, note, xq.snapshot_src == 'file' and C.muted or (l and C.ok or C.err)
  end
  local l = xq.pick and XQ.layout_by_file(xq.pick)
  if l then
    local keys = {}
    for k = 1, 61 do keys[k] = { note = l.notes[k], col = l.colours[k] } end
    return keys, 'Layout: ' .. l.name, 'file only, not confirmed by the keyboard', C.armed
  end
  return nil, 'Layout: unknown / not read yet', 'press "Read from keyboard" in the inspector', C.muted
end

-- ================================================================================================
-- 7. Top bar
-- ================================================================================================
local function do_apply()
  local ok, msg = apply.apply(model)
  if ok and state.reset then state.reset() end   -- ReaLearn parameters restart at 0 after a reload
  apply_running = false
  status.text, status.col = tostring(msg), ok and C.ok or C.err
  errors = M.validate(model)
end
local function do_save()
  local ok, err = M.save(model, apply.MODEL_PATH)
  status.text, status.col = ok and ('Saved ' .. apply.MODEL_PATH) or ('Save failed: ' .. tostring(err)), ok and C.ok or C.err
end
local function do_reload()
  push_undo()
  local m, src = apply.load_model()
  model = m; name_cache = {}
  if type(model.exquis) == 'table' then M.exquis_migrate(model.exquis) end
  view.xmode = 1
  after_edit('Reloaded ' .. tostring(src))
end
local function do_reset()
  push_undo()
  model = M.default()
  if type(model.exquis) == 'table' then M.exquis_migrate(model.exquis) end
  view.xmode = 1
  after_edit('Reset to the shipped default layout')
end

-- Device switch (top-left of row 1); switching drops the selection so the other panel never sees it
local function draw_device_switch()
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, 'Device:'); ImGui.SameLine(ctx)
  for _, d in ipairs(DEVICES) do
    push_id('dev_' .. d.id)
    local selected = view.device == d.id
    if selected then push_col(ImGui.Col_Button, 0x4A6FA5FF); push_col(ImGui.Col_ButtonHovered, 0x5A80B8FF); push_col(ImGui.Col_ButtonActive, 0x3A5F95FF) end
    if ImGui.Button(ctx, d.name) and not selected then
      view.device = d.id
      sel = { kind = nil }
      reaper.SetExtState(EXT, 'device', d.id, true)
    end
    if selected then pop_col(3) end
    pop_id(); ImGui.SameLine(ctx)
  end
  ImGui.Dummy(ctx, 12, 0); ImGui.SameLine(ctx)
end

-- Oxygen Pro 61 rows of the top bar (layouts / pad mode / bank / layer, then the runtime view); ends with SameLine
local function draw_topbar_oxygen()
  -- row 1: layouts
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, 'Layout:'); ImGui.SameLine(ctx)
  for i, l in ipairs(layouts()) do
    push_id('lay' .. i)
    local selected = i == view.layout
    if selected then push_col(ImGui.Col_Button, 0x4A6FA5FF); push_col(ImGui.Col_ButtonHovered, 0x5A80B8FF); push_col(ImGui.Col_ButtonActive, 0x3A5F95FF) end
    if ImGui.Button(ctx, tostring(l.name or l.id or i)) then view.layout = i; view.follow = false end
    if selected then pop_col(3) end
    pop_id(); ImGui.SameLine(ctx)
  end
  if ImGui.Button(ctx, '+##addlayout') then add_layout() end
  ImGui.SetItemTooltip(ctx, 'Add a layout (copy of the current one)')
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Layout settings') then sel = { kind = 'layout' } end
  ImGui.SameLine(ctx); ImGui.Dummy(ctx, 12, 0); ImGui.SameLine(ctx)

  -- pad mode
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, 'Pad mode:'); ImGui.SameLine(ctx)
  local modes = cur_modes()
  local items = {}
  for i, pm in ipairs(modes) do items[i] = { id = i, name = i .. ': ' .. tostring(pm.name or '?') .. ' (' .. tostring(pm.kind) .. ')' } end
  local pick = combo_ids('##padmode', items, view.mode, 220)
  if pick then view.mode = pick; view.follow = false end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, '+##addmode') then add_pad_mode() end
  ImGui.SetItemTooltip(ctx, 'Add a pad mode to every layout (kind: free)')
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, '-##delmode') then remove_pad_mode() end
  ImGui.SetItemTooltip(ctx, 'Remove this pad mode from every layout')
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Edit##mode') then sel = { kind = 'padmode' } end
  ImGui.SameLine(ctx); ImGui.Dummy(ctx, 12, 0); ImGui.SameLine(ctx)

  -- bank
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, 'Bank:'); ImGui.SameLine(ctx)
  local bitems = {}
  for i, b in ipairs(banks()) do bitems[i] = { id = i, name = i .. ': ' .. tostring(b.name or b.kind) } end
  local bpick = combo_ids('##bank', bitems, view.bank, 200)
  if bpick then view.bank = bpick; view.follow = false end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, '+##addbank') then add_bank() end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, '-##delbank') then remove_bank() end
  ImGui.SameLine(ctx); ImGui.Dummy(ctx, 12, 0); ImGui.SameLine(ctx)

  -- layer
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, 'Layer:'); ImGui.SameLine(ctx)
  local litems = { { id = 'normal', name = 'Normal' } }
  for _, mid in ipairs(modifier_ids()) do litems[#litems + 1] = { id = mid, name = layer_label(mid) } end
  local lpick = combo_ids('##layer', litems, view.layer, 150)
  if lpick then view.layer = lpick; view.follow = false end
  ImGui.SameLine(ctx)
  local mods_open = view.show_modifiers   -- capture before the click toggles it, so push and pop always match
  if mods_open then push_col(ImGui.Col_Button, 0x4A6FA5FF); push_col(ImGui.Col_ButtonHovered, 0x5A80B8FF); push_col(ImGui.Col_ButtonActive, 0x3A5F95FF) end
  if ImGui.Button(ctx, 'Modifiers...') then view.show_modifiers = not view.show_modifiers end
  if mods_open then pop_col(3) end
  ImGui.SetItemTooltip(ctx, 'Show / hide the modifier management section (external hold modifiers such as a foot switch)')

  -- row 2: runtime view + actions
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, 'Fader buttons:'); ImGui.SameLine(ctx)
  local fbi = {}
  for i, n in ipairs(FB_MODES) do fbi[i] = { id = i - 1, name = n } end
  local fbp = combo_ids('##fbmode', fbi, view.fb_mode, 90)
  if fbp then view.fb_mode = fbp end
  ImGui.SameLine(ctx)
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, 'Knobs:'); ImGui.SameLine(ctx)
  local kfi = {}
  for i, n in ipairs(KNOB_FNS) do kfi[i] = { id = i - 1, name = n } end
  local kfp = combo_ids('##knobfn', kfi, view.knob_fn, 170)
  if kfp then view.knob_fn = kfp end
  ImGui.SameLine(ctx)
  local rv, nf = ImGui.Checkbox(ctx, 'Follow keyboard', view.follow)
  if rv then view.follow = nf end
  ImGui.SetItemTooltip(ctx, 'Show the layout / pad mode / bank / layer of the running ReaLearn unit')
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 110)
  local zr, nz = ImGui.SliderDouble(ctx, 'Zoom', view.zoom, 0.6, 1.8, '%.2f')
  if zr then view.zoom = nz; reaper.SetExtState(EXT, 'zoom', tostring(nz), true) end
  ImGui.SameLine(ctx); ImGui.Dummy(ctx, 12, 0); ImGui.SameLine(ctx)
end

-- Exquis rows of the top bar (enabled + mode + layer, then slider mode / follow / zoom); ends with SameLine like the Oxygen rows
local function draw_topbar_exquis()
  local x = exquis()
  -- row 1: enabled + mode + layer
  local rv, ne = ImGui.Checkbox(ctx, 'Exquis enabled', x.enabled == true)
  if rv and ne ~= (x.enabled == true) then
    push_undo(); x.enabled = ne; after_edit(ne and 'Exquis section enabled (written on Apply)' or 'Exquis section disabled (no Exquis preset is written)')
  end
  ImGui.SetItemTooltip(ctx, EXQUIS_HINT)
  ImGui.SameLine(ctx); ImGui.Dummy(ctx, 12, 0); ImGui.SameLine(ctx)

  -- mode: combo over model.exquis.modes, add / remove, settings toggle
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, 'Mode:'); ImGui.SameLine(ctx)
  local mitems = {}
  for i, m in ipairs(x.modes) do mitems[i] = { id = i, name = i .. ': ' .. tostring(m.name or ('Mode ' .. i)) } end
  local mpick = combo_ids('##xmode', mitems, view.xmode, 170)
  if mpick then view.xmode = mpick; view.follow = false end
  ImGui.SetItemTooltip(ctx, 'Exquis mode being edited (model.exquis.modes[N]): a full set of button / encoder / push / slider assignments.\nA button or push set to "Next / Previous Exquis mode" steps through the modes on the device.')
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, '+##addxmode') then add_xmode() end
  ImGui.SetItemTooltip(ctx, 'Add an Exquis mode (copy of the current one, at most 8)')
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, '-##delxmode') then remove_xmode() end
  ImGui.SetItemTooltip(ctx, 'Remove the current Exquis mode (at least one stays)')
  ImGui.SameLine(ctx)
  local xset_open = view.show_xmode   -- capture before the click toggles it, so push and pop always match
  if xset_open then push_col(ImGui.Col_Button, 0x4A6FA5FF); push_col(ImGui.Col_ButtonHovered, 0x5A80B8FF); push_col(ImGui.Col_ButtonActive, 0x3A5F95FF) end
  if ImGui.Button(ctx, 'Mode settings##xmodeset') then view.show_xmode = not view.show_xmode end
  if xset_open then pop_col(3) end
  ImGui.SetItemTooltip(ctx, 'Show / hide the mode name and colour in the inspector')
  ImGui.SameLine(ctx); ImGui.Dummy(ctx, 12, 0); ImGui.SameLine(ctx)

  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, 'Layer:'); ImGui.SameLine(ctx)
  local lpick = combo_ids('##xlayer', EXQUIS_LAYERS, view.xlayer, 170)
  if lpick then view.xlayer = lpick end
  ImGui.SetItemTooltip(ctx, 'Normal: modes[N].buttons / encoders.  Shift: modes[N].shift, active while the FCB1010 foot switch is held.\nEncoder pushes and slider zones have no shift layer.')

  -- row 2: slider mode + follow + zoom
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, 'Slider:'); ImGui.SameLine(ctx)
  local smode = x.slider_mode == 'zones' and 'zones' or 'native'
  local spick = combo_ids('##xslidermode', M.EXQUIS_SLIDER_MODES, smode, 300)
  if spick and spick ~= smode then
    push_undo(); x.slider_mode = spick
    if spick == 'native' and sel.dev == 'exquis' and sel.kind == 'slider' then sel = { kind = nil } end
    after_edit(spick == 'native' and 'Slider: native arpeggiator rate (the six zones are not taken over)' or 'Slider: six zones as REAPER buttons (CC 80-85)')
  end
  ImGui.SetItemTooltip(ctx, 'model.exquis.slider_mode: native keeps the keyboard\'s own arpeggiator-rate slider; zones takes the slider over as six buttons (per mode)')
  ImGui.SameLine(ctx); ImGui.Dummy(ctx, 12, 0); ImGui.SameLine(ctx)
  local fr, nf = ImGui.Checkbox(ctx, 'Follow keyboard##xfollow', view.follow)
  if fr then view.follow = nf end
  ImGui.SetItemTooltip(ctx, 'Show the Exquis mode of the running ReaLearn unit (the device echoes its mode presses)')
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 110)
  local zr, nz = ImGui.SliderDouble(ctx, 'Zoom##xzoom', view.zoom, 0.6, 1.8, '%.2f')
  if zr then view.zoom = nz; reaper.SetExtState(EXT, 'zoom', tostring(nz), true) end
  ImGui.SameLine(ctx); ImGui.Dummy(ctx, 12, 0); ImGui.SameLine(ctx)
end

local function draw_topbar()
  draw_device_switch()
  if view.device == 'exquis' then draw_topbar_exquis() else draw_topbar_oxygen() end

  if (function() local r = ImGui.Button(ctx, 'Apply'); if r then last_action = 'Apply' end; return r end)() and not apply_running then apply_running = true; pending_apply = true end
  ImGui.SetItemTooltip(ctx, 'Generate the preset, back up the current one, write it and reload ReaLearn')
  ImGui.SameLine(ctx)
  if (function() local r = ImGui.Button(ctx, 'Save'); if r then last_action = 'Save' end; return r end)() then do_save() end
  ImGui.SameLine(ctx)
  if (function() local r = ImGui.Button(ctx, 'Reload'); if r then last_action = 'Reload' end; return r end)() then do_reload() end
  ImGui.SameLine(ctx)
  if (function() local r = ImGui.Button(ctx, 'Reset to default'); if r then last_action = 'Reset to default' end; return r end)() then do_reset() end
  ImGui.SameLine(ctx)
  ImGui.SameLine(ctx)
  begin_disabled(#undo_stack == 0)
  if (function() local r = ImGui.Button(ctx, 'Undo'); if r then last_action = 'Undo' end; return r end)() then undo() end
  end_disabled()
  ImGui.SameLine(ctx)
  begin_disabled(#redo_stack == 0)
  if (function() local r = ImGui.Button(ctx, 'Redo'); if r then last_action = 'Redo' end; return r end)() then redo() end
  end_disabled()
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, ImGui.IsWindowDocked(ctx) and 'Undock' or 'Dock') then
    pending_dock = ImGui.IsWindowDocked(ctx) and 0 or -1
  end

  -- status line + validation
  if status.col then ImGui.TextColored(ctx, status.col, status.text) else ImGui.Text(ctx, status.text) end
  if type(model.exquis) == 'table' and model.exquis.enabled then
    ImGui.SameLine(ctx); ImGui.TextColored(ctx, C.ok, '  |  Exquis section: enabled')
  elseif view.device == 'exquis' then
    ImGui.SameLine(ctx); ImGui.TextDisabled(ctx, '  |  Exquis section: off (no Exquis preset is written)')
  end
  if last_error then
    ImGui.TextColored(ctx, C.err, 'Script error: ' .. tostring(last_error)); ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, 'Clear') then last_error = nil end
  end
  if #errors > 0 then
    for i, e in ipairs(errors) do
      if i > 4 then ImGui.TextColored(ctx, C.err, string.format('... and %d more validation errors', #errors - 4)); break end
      ImGui.TextColored(ctx, C.err, e)
    end
  end
end

-- ================================================================================================
-- 8. Panel drawing
-- ================================================================================================
local PANEL_W, PANEL_H = 1150, 292
local G = { ox = 0, oy = 0, z = 1, dl = nil }

local function X(x) return G.ox + x * G.z end
local function Y(y) return G.oy + y * G.z end

local function rect(x, y, w, h, col, rounding, outline)
  ImGui.DrawList_AddRectFilled(G.dl, X(x), Y(y), X(x + w), Y(y + h), col, (rounding or 0) * G.z)
  if outline then ImGui.DrawList_AddRect(G.dl, X(x), Y(y), X(x + w), Y(y + h), outline, (rounding or 0) * G.z) end
end
local function outline(x, y, w, h, col, thick, rounding)
  ImGui.DrawList_AddRect(G.dl, X(x) - 1, Y(y) - 1, X(x + w) + 1, Y(y + h) + 1, col, (rounding or 0) * G.z, ImGui.DrawFlags_None, thick or 1)
end

local function measure(s, fs)
  ImGui.PushFont(ctx, nil, fs)
  local w, h = ImGui.CalcTextSize(ctx, s)
  ImGui.PopFont(ctx)
  return w, h
end

-- text centred in a box (x,y,w,h); wraps left-aligned when it does not fit on one line
local function label(x, y, w, h, s, col, size)
  if not s or s == '' then return end
  local fs = (size or 10) * G.z
  local tw, th = measure(s, fs)
  local bw = w * G.z
  if tw <= bw then
    ImGui.DrawList_AddTextEx(G.dl, font, fs, X(x) + (bw - tw) / 2, Y(y) + (h and ((h * G.z - th) / 2) or 0), col, s)
  else
    ImGui.DrawList_AddTextEx(G.dl, font, fs, X(x), Y(y), col, s, bw)
  end
end

-- hit area at unscaled coords; returns clicked, hovered
local function hit(id, x, y, w, h)
  ImGui.SetCursorScreenPos(ctx, X(x), Y(y))
  local clicked = ImGui.InvisibleButton(ctx, id, math.max(1, w * G.z), math.max(1, h * G.z))
  return clicked, ImGui.IsItemHovered(ctx)
end

local function is_sel(kind, a, b)
  if sel.dev or sel.kind ~= kind then return false end   -- sel.dev = an Exquis selection, never an Oxygen one
  if kind == 'button' then return sel.id == a end
  if kind == 'pad' then return sel.k == a end
  if kind == 'bank' then return sel.sub == a and sel.i == b end
  return true
end

-- a panel push button: id may be nil for hardware-only buttons
local function panel_button(id, x, y, w, h, caption, fn_text, tip)
  local clicked, hovered = false, false
  if id then clicked, hovered = hit('btn_' .. id, x, y, w, h) end
  local fill = id and (hovered and C.btn_hover or C.btn) or C.btn_static
  rect(x, y, w, h, fill, 4, C.line)
  label(x, y, w, h, caption, id and C.ink or C.muted, 10)
  if id and is_sel('button', id) then outline(x, y, w, h, C.sel, 2, 4) end
  if id and live and view.follow and live['mod_' .. id] == 1 then outline(x, y, w, h, C.armed, 2, 4) end
  label(x - 4, y + h + 3, w + 8, nil, fn_text, C.ink, 9)
  if hovered and tip then ImGui.SetTooltip(ctx, tip) end
  if clicked then sel = { kind = 'button', id = id } end
end

local function draw_left()
  rect(14, 22, 16, 12, C.btn, 2, C.line); rect(34, 22, 16, 12, C.btn, 2, C.line)
  label(8, 37, 50, nil, 'oct - / +', C.muted, 8)
  rect(16, 52, 14, 64, C.track, 7, C.line); rect(38, 52, 14, 64, C.track, 7, C.line)
  label(8, 118, 50, nil, 'pitch  mod', C.muted, 8)
  rect(12, 135, 60, 150, C.keys, 3, C.line)
  label(12, 200, 60, nil, '61 keys', C.black, 10)
  label(8, 6, 60, nil, 'M-AUDIO', C.ink, 9)
end

local function draw_faders()
  local b = cur_bank()
  local FX0 = 88
  for i = 1, 9 do
    local cx = FX0 + (i - 1) * 30 + 13
    local clicked, hovered = hit('fader' .. i, cx - 14, 30, 28, 96)
    label(cx - 14, 18, 28, nil, tostring(i), C.muted, 8)
    rect(cx - 3, 32, 6, 90, C.track, 2, C.line)
    local capy = (i == 9) and 60 or 74
    rect(cx - 9, capy, 18, 12, hovered and C.btn_hover or C.cap, 2, C.line)
    if is_sel('bank', 'fader', i) then outline(cx - 12, 30, 24, 96, C.sel, 2, 3) end
    label(cx - 16, 124, 32, nil, fader_text(b, i), C.ink, 8)
    if clicked then sel = { kind = 'bank', sub = 'fader', i = i } end
    if hovered then ImGui.SetTooltip(ctx, 'Fader ' .. i .. ' (CC ' .. (i == 9 and 41 or 11 + i) .. '): ' .. fader_text(b, i) .. '\nClick to edit bank ' .. view.bank) end
  end
  -- fader buttons 1-8
  for i = 1, 8 do
    local cx = FX0 + (i - 1) * 30 + 13
    local clicked, hovered = hit('fbtn' .. i, cx - 12, 158, 24, 18)
    rect(cx - 12, 158, 24, 18, hovered and C.btn_hover or C.btn, 3, C.line)
    label(cx - 12, 158, 24, 18, tostring(i), C.ink, 9)
    if is_sel('bank', 'fbtn', i) then outline(cx - 12, 158, 24, 18, C.sel, 2, 3) end
    label(cx - 16, 179, 32, nil, fbtn_text(b, i, view.fb_mode), C.ink, 8)
    if clicked then sel = { kind = 'bank', sub = 'fbtn', i = i } end
    if hovered then ImGui.SetTooltip(ctx, 'Fader button ' .. i .. ' in mode "' .. FB_MODES[view.fb_mode + 1] .. '": ' .. fbtn_text(b, i, view.fb_mode)) end
  end
  -- Mode button + LEDs under fader 9
  local cx = FX0 + 8 * 30 + 13
  local clicked, hovered = hit('modebtn', cx - 14, 158, 28, 18)
  rect(cx - 14, 158, 28, 18, hovered and C.btn_hover or C.btn, 3, C.line)
  label(cx - 14, 158, 28, 18, 'Mode', C.ink, 8)
  if clicked then view.fb_mode = (view.fb_mode + 1) % 5; view.follow = false end
  if hovered then ImGui.SetTooltip(ctx, 'Fader-button mode (cycles the displayed mode)') end
  for m = 0, 4 do
    local ly = 182 + m * 10
    local on = (m == view.fb_mode)
    ImGui.DrawList_AddCircleFilled(G.dl, X(cx - 10), Y(ly + 3), 2.5 * G.z, on and C.sel or C.dim)
    ImGui.DrawList_AddTextEx(G.dl, font, 7 * G.z, X(cx - 5), Y(ly - 1), on and C.ink or C.muted, FB_MODES[m + 1])
  end
  -- bank title
  local title = string.format('Bank %d/%d: %s  [%s]', view.bank, #banks(), tostring(b and b.name or '?'), tostring(b and b.kind or '?'))
  ImGui.DrawList_AddTextEx(G.dl, font, 10 * G.z, X(FX0), Y(240), C.muted, title)
  ImGui.DrawList_AddTextEx(G.dl, font, 9 * G.z, X(FX0), Y(254), C.muted,
    'Fader buttons: ' .. FB_MODES[view.fb_mode + 1] .. '   Knobs: ' .. KNOB_FNS[view.knob_fn + 1])
  if live and view.follow then
    ImGui.DrawList_AddTextEx(G.dl, font, 9 * G.z, X(FX0), Y(268), C.live,
      string.format('LIVE  bank %d  fader-button mode %s  knob fn %s', (live.bank or 0) + 1, FB_MODES[(live.mode or 0) + 1] or '?', KNOB_SHORT[(live.knob or 0) + 1] or '?'))
  end
end

local function draw_centre()
  local CX0, W, H, S = 375, 50, 22, 56
  local function bx(i) return CX0 + (i - 1) * S end
  local function fn(id) return assignment_text(layer_assignment(id)) end
  local function tip(id)
    local c = M.CONTROL_BY_ID[id]
    return c.name .. ' (CC ' .. c.cc .. ')\n' .. layer_label(view.layer) .. ': ' .. assignment_text(layer_assignment(id), true)
  end
  -- row 1
  panel_button('daw', bx(1), 22, W, H, 'DAW', fn('daw'), tip('daw'))
  panel_button(nil, bx(2), 22, W, H, 'Preset', '(hardware)')
  panel_button(nil, bx(3), 22, W, H, 'Tempo', '(hardware)')
  panel_button('bank_prev', bx(4), 22, W, H, '< Bank', fn('bank_prev'), tip('bank_prev'))
  panel_button('bank_next', bx(5), 22, W, H, 'Bank >', fn('bank_next'), tip('bank_next'))
  panel_button(nil, bx(6), 22, W, H, 'Note rpt', '(hardware)')
  -- row 2
  panel_button(nil, bx(1), 90, W, H, 'Shift', '(hardware)')
  local l, pm = cur_layout(), cur_mode()
  local disp = string.format('%s / %s', tostring(l and l.name or '?'), tostring(pm and pm.name or '?'))
  rect(bx(2), 90, S + W, H, 0x0A1A10FF, 3, C.line)
  label(bx(2), 90, S + W, H, disp, 0x7FE0A0FF, 9)
  if live and view.follow then label(bx(2), 90 + H + 3, S + W, nil, 'LIVE', C.live, 8)
  elseif view.follow then label(bx(2), 90 + H + 3, S + W, nil, 'no Helgobox', C.err, 8) end
  panel_button('rewind', bx(4), 90, W, H, '<<', fn('rewind'), tip('rewind'))
  panel_button('ffwd', bx(5), 90, W, H, '>>', fn('ffwd'), tip('ffwd'))
  panel_button('loop', bx(6), 90, W, H, 'Loop', fn('loop'), tip('loop'))
  -- row 3
  panel_button('back', bx(1), 158, W, H, 'Back', fn('back'), tip('back'))
  -- encoder: outer ring = turn, centre = press
  local ecx, ecy, r = bx(2) + W / 2 + 14, 158 + H / 2, 17
  local clicked, hovered = hit('encoder', ecx - r, ecy - r, 2 * r, 2 * r)
  ImGui.DrawList_AddCircleFilled(G.dl, X(ecx), Y(ecy), r * G.z, hovered and C.btn_hover or C.knob)
  ImGui.DrawList_AddCircle(G.dl, X(ecx), Y(ecy), r * G.z, C.line, 0, 1)
  ImGui.DrawList_AddCircleFilled(G.dl, X(ecx), Y(ecy), 8 * G.z, C.btn)
  ImGui.DrawList_AddLine(G.dl, X(ecx), Y(ecy - r + 2), X(ecx), Y(ecy - r + 7), C.ink, 2)
  if sel.kind == 'encoder' and not sel.dev then ImGui.DrawList_AddCircle(G.dl, X(ecx), Y(ecy), (r + 2) * G.z, C.sel, 0, 2) end
  if is_sel('button', 'encoder_press') then ImGui.DrawList_AddCircle(G.dl, X(ecx), Y(ecy), 9 * G.z, C.sel, 0, 2) end
  local turn = encoder_text(layer_encoder())
  label(ecx - 32, ecy + r + 3, 64, nil, 'Turn: ' .. turn, C.ink, 8)
  label(ecx - 32, ecy + r + 14, 64, nil, 'Push: ' .. fn('encoder_press'), C.ink, 8)
  if hovered then
    ImGui.SetTooltip(ctx, 'Encoder\nTurn (ring): ' .. encoder_text(layer_encoder(), true) .. '\nPress (centre): ' .. assignment_text(layer_assignment('encoder_press'), true))
  end
  if clicked then
    local mx, my = ImGui.GetMousePos(ctx)
    local dx, dy = (mx - X(ecx)) / G.z, (my - Y(ecy)) / G.z
    if dx * dx + dy * dy <= 81 then sel = { kind = 'button', id = 'encoder_press' } else sel = { kind = 'encoder' } end
  end
  panel_button('stop', bx(4), 158, W, H, 'Stop', fn('stop'), tip('stop'))
  panel_button('play', bx(5), 158, W, H, 'Play', fn('play'), tip('play'))
  panel_button('record', bx(6), 158, W, H, 'Rec', fn('record'), tip('record'))
  -- layer / live line
  local layer_name
  if view.layer == 'normal' then layer_name = 'Normal layer'
  elseif is_external(view.layer) then layer_name = layer_label(view.layer) .. ' layer (while held)'
  else layer_name = layer_label(view.layer) .. ' (modifier armed)' end
  ImGui.DrawList_AddTextEx(G.dl, font, 10 * G.z, X(CX0), Y(240), view.layer == 'normal' and C.muted or C.armed, layer_name)
  if live and view.follow then
    local armed = {}
    for _, mid in ipairs(modifier_ids()) do if live['mod_' .. mid] == 1 then armed[#armed + 1] = M.modifier_name(model, mid) end end
    ImGui.DrawList_AddTextEx(G.dl, font, 9 * G.z, X(CX0), Y(254), C.live,
      string.format('LIVE  layout %d  pad mode %d  armed: %s', (live.layout or 0) + 1, (live.pad or 0) + 1, #armed > 0 and table.concat(armed, ', ') or 'none'))
  end
end

local function draw_right()
  local b = cur_bank()
  local KX0, S = 730, 47
  -- knobs
  for i = 1, 8 do
    local cx, cy, r = KX0 + (i - 1) * S + 22, 40, 13
    local clicked, hovered = hit('knob' .. i, cx - r, cy - r, 2 * r, 2 * r)
    label(cx - 20, 14, 40, nil, tostring(i), C.muted, 8)
    ImGui.DrawList_AddCircleFilled(G.dl, X(cx), Y(cy), r * G.z, hovered and C.btn_hover or C.knob)
    ImGui.DrawList_AddCircle(G.dl, X(cx), Y(cy), r * G.z, C.line, 0, 1)
    ImGui.DrawList_AddLine(G.dl, X(cx), Y(cy - r + 2), X(cx), Y(cy - r + 8), C.ink, 2)
    if is_sel('bank', 'knob', i) then ImGui.DrawList_AddCircle(G.dl, X(cx), Y(cy), (r + 2) * G.z, C.sel, 0, 2) end
    label(cx - 23, cy + r + 3, 46, nil, knob_text(b, i, view.knob_fn), C.ink, 8)
    if clicked then sel = { kind = 'bank', sub = 'knob', i = i } end
    if hovered then ImGui.SetTooltip(ctx, 'Knob ' .. i .. ' (CC ' .. (21 + i) .. ') with function "' .. KNOB_FNS[view.knob_fn + 1] .. '": ' .. knob_text(b, i, view.knob_fn)) end
  end
  -- pads
  local PW = 44
  for k = 1, 16 do
    local col = (k - 1) % 8
    local row = (k <= 8) and 0 or 1
    local px, py = KX0 + col * S, 96 + row * 51
    local clicked, hovered = hit('pad' .. k, px, py, PW, PW)
    local fill, short, long = pad_info(k)
    rect(px, py, PW, PW, fill, 5, hovered and C.white or C.line)
    local ink = ink_for(fill)
    ImGui.DrawList_AddTextEx(G.dl, font, 7 * G.z, X(px + 3), Y(py + 2), ink, tostring(k))
    label(px + 2, py + 13, PW - 4, nil, short, ink, 8)
    if is_sel('pad', k) then outline(px, py, PW, PW, C.sel, 2, 5) end
    if clicked then sel = { kind = 'pad', k = k } end
    if hovered then ImGui.SetTooltip(ctx, 'Pad ' .. k .. ': ' .. long) end
  end
  -- side buttons
  local sx = KX0 + 8 * S + 4
  local function side(id, y, caption)
    local clicked, hovered = hit('btn_' .. id, sx, y, 26, PW)
    rect(sx, y, 26, PW, hovered and C.btn_hover or C.btn, 4, C.line)
    label(sx, y, 26, PW, caption, C.ink, 10)
    if is_sel('button', id) then outline(sx, y, 26, PW, C.sel, 2, 4) end
    if clicked then sel = { kind = 'button', id = id } end
    if hovered then ImGui.SetTooltip(ctx, M.CONTROL_BY_ID[id].name .. ': ' .. assignment_text(layer_assignment(id), true)) end
  end
  side('side_top', 96, '^')
  side('side_bottom', 147, 'v')
  -- titles
  local pm = cur_mode()
  ImGui.DrawList_AddTextEx(G.dl, font, 9 * G.z, X(KX0), Y(196), C.ink,
    'Side top: ' .. assignment_text(layer_assignment('side_top')) .. '    Side bottom: ' .. assignment_text(layer_assignment('side_bottom')))
  ImGui.DrawList_AddTextEx(G.dl, font, 10 * G.z, X(KX0), Y(212), C.muted,
    string.format('Pads: mode %d/%d "%s" [%s]', view.mode, #cur_modes(), tostring(pm and pm.name or '?'), tostring(pm and pm.kind or '?')))
  ImGui.DrawList_AddTextEx(G.dl, font, 9 * G.z, X(KX0), Y(226), C.muted, 'Knobs: ' .. KNOB_FNS[view.knob_fn + 1])
end

local function draw_panel()
  G.ox, G.oy = ImGui.GetCursorScreenPos(ctx)
  G.z = view.zoom
  G.dl = ImGui.GetWindowDrawList(ctx)
  rect(0, 0, PANEL_W, PANEL_H, C.bg, 12)
  ImGui.DrawList_AddLine(G.dl, X(80), Y(10), X(80), Y(PANEL_H - 10), C.line, 1)
  ImGui.DrawList_AddLine(G.dl, X(366), Y(10), X(366), Y(PANEL_H - 10), C.line, 1)
  ImGui.DrawList_AddLine(G.dl, X(720), Y(10), X(720), Y(PANEL_H - 10), C.line, 1)
  draw_left()
  draw_faders()
  draw_centre()
  draw_right()
  ImGui.SetCursorScreenPos(ctx, G.ox, G.oy)
  ImGui.Dummy(ctx, PANEL_W * G.z, PANEL_H * G.z)
end

-- ---- Exquis panel ------------------------------------------------------------------------------------
local EXQ_W, EXQ_H = 660, 620

local function xsel(kind, id) return sel.dev == 'exquis' and sel.kind == kind and sel.id == id end
local function xselect(kind, id) sel = { dev = 'exquis', kind = kind, id = id } end

local function draw_exquis_panel()
  G.ox, G.oy = ImGui.GetCursorScreenPos(ctx)
  G.z = view.zoom
  G.dl = ImGui.GetWindowDrawList(ctx)
  local x = exquis()
  local m = cur_xmode()
  local mcol = EXQUIS_RGBA[m.colour or 'white'] or RGBA.off   -- mode colour: LED of mode_next / mode_prev controls
  local layer = view.xlayer
  local shift = layer == 'shift'
  local btns, encs, pushes, slider = xbuttons_of(layer), xencoders_of(layer), m.pushes, m.slider
  local native = x.slider_mode ~= 'zones'   -- the keyboard keeps its arpeggiator-rate slider
  local lname = xlayer_name(layer)
  rect(0, 0, EXQ_W, EXQ_H, C.bg, 12)
  ImGui.DrawList_AddTextEx(G.dl, font, 9 * G.z, X(14), Y(6), C.ink, 'INTUITIVE INSTRUMENTS   Exquis')
  -- header line: mode swatch + name, live mode, layer
  rect(180, 7, 10, 10, mcol, 2, C.line)
  local mtitle = string.format('Mode %d/%d: %s', view.xmode, #x.modes, tostring(m.name or '?'))
  ImGui.DrawList_AddTextEx(G.dl, font, 9 * G.z, X(195), Y(6), C.ink, mtitle)
  if live and view.follow then
    local tw = measure(mtitle, 9 * G.z)
    ImGui.DrawList_AddTextEx(G.dl, font, 9 * G.z, X(195) + tw + 10 * G.z, Y(6), C.live,
      string.format('LIVE  mode %d', math.floor(tonumber(live.xmode) or 0) + 1))
  elseif view.follow then
    local tw = measure(mtitle, 9 * G.z)
    ImGui.DrawList_AddTextEx(G.dl, font, 9 * G.z, X(195) + tw + 10 * G.z, Y(6), C.err, 'no Helgobox')
  end
  ImGui.DrawList_AddTextEx(G.dl, font, 9 * G.z, X(EXQ_W - 200), Y(6), shift and C.armed or C.muted,
    shift and 'Shift layer (FCB1010 held)' or 'Normal layer')
  if not x.enabled then
    ImGui.DrawList_AddTextEx(G.dl, font, 9 * G.z, X(14), Y(EXQ_H - 14), C.err,
      'Section disabled: no Exquis preset is written on Apply (tick "Exquis enabled" in the top bar)')
  end

  -- encoders (CC 110-113): ring = turn, centre = push (CC 114-117); push text under each
  for i = 1, 4 do
    local a, p = encs[i], pushes[i]
    local cx, cy, r = 100 + (i - 1) * 150, 62, 20
    local clicked, hovered = hit('xenc' .. i, cx - r - 5, cy - r - 5, 2 * r + 10, 2 * r + 10)
    label(cx - 65, 22, 130, nil, string.format('Encoder %d  (CC %d)', i, EXQUIS_ENC_CC[i]), C.muted, 8)
    ImGui.DrawList_AddCircle(G.dl, X(cx), Y(cy), (r + 4) * G.z, xcolour(a), 0, 3 * G.z)      -- LED ring
    ImGui.DrawList_AddCircleFilled(G.dl, X(cx), Y(cy), r * G.z, hovered and C.btn_hover or C.knob)
    ImGui.DrawList_AddCircle(G.dl, X(cx), Y(cy), r * G.z, hovered and C.white or C.line, 0, 1)
    ImGui.DrawList_AddCircleFilled(G.dl, X(cx), Y(cy), 8 * G.z, C.btn)
    ImGui.DrawList_AddLine(G.dl, X(cx), Y(cy - r + 2), X(cx), Y(cy - r + 8), C.ink, 2)
    if xsel('encoder', i) then ImGui.DrawList_AddCircle(G.dl, X(cx), Y(cy), (r + 7) * G.z, C.sel, 0, 2) end
    if xsel('push', i) then ImGui.DrawList_AddCircle(G.dl, X(cx), Y(cy), 9 * G.z, C.sel, 0, 2) end
    label(cx - 70, cy + r + 8, 140, nil, xencoder_text(a), C.ink, 9)
    local py = cy + r + 22
    local pclicked, phovered = hit('xpush' .. i, cx - 65, py, 130, 14)
    rect(cx - 65, py, 130, 14, phovered and C.btn_hover or C.btn_static, 3, phovered and C.white or C.line)
    ImGui.DrawList_AddCircleFilled(G.dl, X(cx - 58), Y(py + 7), 3 * G.z, xcolour(p, mcol))    -- push LED (mode colour for mode steps)
    label(cx - 52, py, 117, 14, 'Push: ' .. xpush_text(p), C.ink, 8)
    if xsel('push', i) then outline(cx - 65, py, 130, 14, C.sel, 2, 3) end
    if hovered then
      ImGui.SetTooltip(ctx, string.format('Encoder %d (CC %d; ring = turn, centre = push)\n%s: %s\nPush (CC %d, no shift layer): %s',
        i, EXQUIS_ENC_CC[i], lname, xencoder_text(a, true), EXQUIS_PUSH_CC[i], xpush_text(p, true)))
    end
    if phovered then ImGui.SetTooltip(ctx, string.format('Encoder %d push (CC %d, no shift layer): %s', i, EXQUIS_PUSH_CC[i], xpush_text(p, true))) end
    if clicked then
      local mx, my = ImGui.GetMousePos(ctx)
      local dx, dy = (mx - X(cx)) / G.z, (my - Y(cy)) / G.z
      if dx * dx + dy * dy <= 81 then xselect('push', i) else xselect('encoder', i) end
    end
    if pclicked then xselect('push', i) end
  end

  -- slider: six zones (CC 80-85) when taken over; greyed out (not clickable) while the slider stays native
  ImGui.DrawList_AddTextEx(G.dl, font, 8 * G.z, X(40), Y(126), C.muted,
    native and 'Slider: native (arpeggiator rate), not taken over  -  choose "zones" in the top bar for six buttons'
           or 'Slider zones 1-6  (CC 80-85, no shift layer)')
  for k = 1, 6 do
    local a = slider[k]
    local zx, zy, zw, zh = 40 + (k - 1) * 97, 138, 90, 30
    if native then
      rect(zx, zy, zw, zh, C.btn_static, 4, C.line)
      ImGui.DrawList_AddTextEx(G.dl, font, 7 * G.z, X(zx + 3), Y(zy + 2), C.dim, tostring(k))
      label(zx + 4, zy + 4, zw - 8, zh - 8, 'native (arpeggiator rate)', C.dim, 8)
    else
      local clicked, hovered = hit('xsl' .. k, zx, zy, zw, zh)
      local col = xcolour(a)
      local fill = has_colour(a) and half_rgba(col) or (hovered and C.btn_hover or C.btn)
      rect(zx, zy, zw, zh, fill, 4, hovered and C.white or C.line)
      rect(zx + 4, zy + zh - 6, zw - 8, 3, col, 1)                                           -- zone LED
      local ink = ink_for(fill)
      ImGui.DrawList_AddTextEx(G.dl, font, 7 * G.z, X(zx + 3), Y(zy + 2), ink, tostring(k))
      label(zx + 8, zy + 3, zw - 12, 16, xpush_text(a, false, M.EXQUIS_SLIDER_KINDS), ink, 9)
      if xsel('slider', k) then outline(zx, zy, zw, zh, C.sel, 2, 4) end
      if hovered then ImGui.SetTooltip(ctx, string.format('Slider zone %d (CC %d, no shift layer): %s', k, EXQUIS_SLIDER_CC[k], xpush_text(a, true, M.EXQUIS_SLIDER_KINDS))) end
      if clicked then xselect('slider', k) end
    end
  end

  -- buttons: Record, Loop, Clips, Play/Stop  /  Down, Up, Undo, Redo
  local rows = { { 'record', 'loop', 'clips', 'play' }, { 'down', 'up', 'undo', 'redo' } }
  for ri, row in ipairs(rows) do
    for j, id in ipairs(row) do
      local a = btns[id]
      local bx, by, bw, bh = 40 + (j - 1) * 150, 188 + (ri - 1) * 64, 130, 52
      local clicked, hovered = hit('xbtn_' .. id, bx, by, bw, bh)
      local col = xcolour(a, mcol)   -- mode_next / mode_prev without a colour of its own: the mode colour
      local fill = has_colour(a) and half_rgba(col) or (hovered and C.btn_hover or C.btn)
      rect(bx, by, bw, bh, fill, 6, hovered and C.white or C.line)
      rect(bx + 6, by + 5, bw - 12, 4, col, 2)                                                -- button LED
      local ink = ink_for(fill)
      ImGui.DrawList_AddTextEx(G.dl, font, 8 * G.z, X(bx + 6), Y(by + 12), ink,
        string.format('%s  (CC %d)', name_of(M.EXQUIS_BUTTONS, id), EXQUIS_ELEM[id] or 0))
      label(bx + 4, by + 24, bw - 8, 24, xbutton_text(a), ink, 10)
      if xsel('button', id) then outline(bx, by, bw, bh, C.sel, 2, 6) end
      if hovered then
        ImGui.SetTooltip(ctx, string.format('%s (CC %d)\n%s: %s', name_of(M.EXQUIS_BUTTONS, id), EXQUIS_ELEM[id] or 0, lname, xbutton_text(a, true)))
      end
      if clicked then xselect('button', id) end
    end
  end

  -- layout on keyboard: the 61 keys as played (keyboard on its side, encoders to the player's left), coloured and
  -- named from the snapshot read from the device (or a layout file); native MPE, not remapped
  local hx, hy, hw, hh = 20, 320, EXQ_W - 40, EXQ_H - 320 - 24
  rect(hx, hy, hw, hh, 0x17181CFF, 8, C.line)
  local keys, head, note, hcol = XQ.display()
  ImGui.DrawList_AddTextEx(G.dl, font, 9 * G.z, X(hx + 10), Y(hy + 6), C.muted, 'Layout on keyboard  (61 keys, MPE, not remapped)')
  ImGui.DrawList_AddTextEx(G.dl, font, 11 * G.z, X(hx + 10), Y(hy + 20), C.ink, head)
  ImGui.DrawList_AddTextEx(G.dl, font, 8 * G.z, X(hx + 10), Y(hy + 36), hcol, note)
  if xq.pending then ImGui.DrawList_AddTextEx(G.dl, font, 8 * G.z, X(hx + hw - 150), Y(hy + 6), C.live, 'reading ' .. xq.pending .. '...') end
  local hr = 19                                    -- key radius; flat-top hexagons in staggered columns
  local dx, dy = hr * 1.5, hr * 1.7320508
  local gx0 = hx + (hw - (10 * dx + 2 * hr)) / 2 + hr   -- player column 1 (left)
  local gy0 = hy + hh - 10 - hr                     -- key 1 of a 6-key column (bottom)
  local idx = 0
  for row = 1, 11 do
    local count = XQ.ROWS[row]
    local p = 12 - row                              -- file row -> player column (1 = left, 11 = right)
    for k = 1, count do
      idx = idx + 1
      local key = keys and keys[idx]
      local cx = gx0 + (p - 1) * dx
      local cy = gy0 - (k - 1 + (count == 5 and 0.5 or 0)) * dy
      local fill = key and key.col or C.btn
      local _, hovered = hit('xkey' .. idx, cx - hr, cy - hr, 2 * hr, 2 * hr)
      ImGui.DrawList_AddCircleFilled(G.dl, X(cx), Y(cy), (hr - 1.5) * G.z, fill, 6)
      ImGui.DrawList_AddCircle(G.dl, X(cx), Y(cy), (hr - 1.5) * G.z, hovered and C.white or C.line, 6, 1)
      if key then
        label(cx - hr, cy - 6, 2 * hr, 12, XQ.note_name(key.note), ink_for(fill), 8)
        if hovered then
          ImGui.SetTooltip(ctx, string.format('Column %d, key %d: %s (note %d)  #%06X', p, k, XQ.note_name(key.note), key.note, fill >> 8))
        end
      end
    end
  end
  ImGui.DrawList_AddTextEx(G.dl, font, 8 * G.z, X(hx + hw - 150), Y(hy + hh - 14), C.muted, 'encoders <- this side')

  ImGui.SetCursorScreenPos(ctx, G.ox, G.oy)
  ImGui.Dummy(ctx, EXQ_W * G.z, EXQ_H * G.z)
end

-- ================================================================================================
-- 9. Inspector
-- ================================================================================================
local function edit_assignment(uid, resolver, allow_modifier, button_id)
  local a = resolver()
  if type(a) ~= 'table' then return end
  local kinds = { { 'none', 'Nothing' }, { 'builtin', 'Built-in' }, { 'action', 'Action' } }
  if allow_modifier then kinds[4] = { 'modifier', 'Modifier latch' } end
  for i, k in ipairs(kinds) do
    if ImGui.RadioButton(ctx, k[2] .. '##' .. uid, a.kind == k[1]) and a.kind ~= k[1] then
      push_undo(); set_button_kind(a, k[1], allow_modifier and button_id or nil); after_edit()
    end
    if i < #kinds then ImGui.SameLine(ctx) end
  end
  if a.kind == 'builtin' then
    local pick = combo_ids('Function##fn_' .. uid, M.BUILTINS, a.builtin, -FLT_MIN)
    if pick then push_undo(); a.builtin = pick; after_edit() end
  elseif a.kind == 'action' then
    command_widget(uid, resolver, 'command')
  elseif a.kind == 'modifier' then
    local pick = combo_ids('Indicator##' .. uid, M.MODIFIER_INDICATORS, a.indicator, -FLT_MIN)
    if pick then push_undo(); a.indicator = pick; after_edit() end
    ImGui.TextWrapped(ctx, 'Press once to arm the layer; the next button press uses the combo assigned in this button\'s layer (Layer combo in the top bar).')
  elseif a.kind ~= 'none' then
    ImGui.TextColored(ctx, C.err, 'Unknown kind: ' .. tostring(a.kind))
  end
end

local function inspect_button(id)
  local c = M.CONTROL_BY_ID[id]
  if not c then ImGui.Text(ctx, 'Unknown control ' .. tostring(id)); return end
  ImGui.SeparatorText(ctx, c.name .. '  (CC ' .. c.cc .. ')')
  if view.layer == 'normal' then
    ImGui.TextDisabled(ctx, 'Normal layer: model.buttons.' .. id)
    edit_assignment('btn_' .. id, function() return ensure_button(id) end, true, id)
  else
    local mid = view.layer
    ImGui.TextDisabled(ctx, layer_label(mid) .. ': model.modifiers.' .. mid .. '.combos.' .. id)
    if is_external(mid) then
      local e = model.modifiers[mid].external
      ImGui.TextDisabled(ctx, 'Fires while the external modifier is held (CC ' .. tostring(e.cc) .. ' on MIDI channel ' .. tostring((tonumber(e.channel) or M.EXTERNAL_CHANNEL) + 1) .. ')')
    end
    if id == mid and not is_external(mid) then
      ImGui.TextWrapped(ctx, 'This is the modifier button itself; it cannot have a combo in its own layer. Switch to the Normal layer to change what it does.')
      return
    end
    local m = ensure_modifier(mid)
    if type(m.combos[id]) ~= 'table' then m.combos[id] = { kind = 'none' } end
    local a = m.combos[id]
    local per = a.kind == 'per_layout'
    local rv, np = ImGui.Checkbox(ctx, 'Different per layout', per)
    if rv and np ~= per then
      push_undo()
      if np then
        local lay = {}
        for _, l in ipairs(layouts()) do lay[l.id] = M.copy(a) end
        set_table(a, { kind = 'per_layout', layouts = lay })
      else
        local cur = (a.layouts or {})[cur_layout().id] or { kind = 'none' }
        set_table(a, M.copy(cur))
      end
      after_edit()
    end
    if a.kind == 'per_layout' then
      ImGui.TextDisabled(ctx, 'Editing the combo for layout "' .. tostring(cur_layout().name) .. '" (switch layout tabs for the others)')
      local function resolver()
        local mm = (model.modifiers or {})[mid]
        local aa = mm and mm.combos and mm.combos[id]
        if type(aa) ~= 'table' or aa.kind ~= 'per_layout' then return nil end
        aa.layouts = aa.layouts or {}
        local lid = cur_layout().id
        if type(aa.layouts[lid]) ~= 'table' then aa.layouts[lid] = { kind = 'none' } end
        return aa.layouts[lid]
      end
      edit_assignment('combo_' .. mid .. '_' .. id .. '_' .. tostring(cur_layout().id), resolver, false)
    else
      edit_assignment('combo_' .. mid .. '_' .. id, function()
        local mm = (model.modifiers or {})[mid]
        if not (mm and mm.combos) then return nil end
        if type(mm.combos[id]) ~= 'table' then mm.combos[id] = { kind = 'none' } end
        return mm.combos[id]
      end, false)
    end
  end
end

local function inspect_encoder()
  ImGui.SeparatorText(ctx, 'Encoder turn  (CC ' .. M.ENCODER_CC .. ')')
  local function resolver()
    if view.layer == 'normal' then
      if type(model.encoder_turn) ~= 'table' then model.encoder_turn = { kind = 'none' } end
      return model.encoder_turn
    end
    local m = ensure_modifier(view.layer)
    if type(m.encoder_turn) ~= 'table' then m.encoder_turn = { kind = 'none' } end
    return m.encoder_turn
  end
  local e = resolver()
  ImGui.TextDisabled(ctx, view.layer == 'normal' and 'Normal layer: model.encoder_turn' or ('model.modifiers.' .. view.layer .. '.encoder_turn'))
  local pick = combo_ids('Kind##enc', M.ENCODER_KINDS, e.kind, -FLT_MIN)
  if pick then push_undo(); set_table(e, { kind = pick }); after_edit() end
  if e.kind == 'actions' then
    ImGui.Text(ctx, 'Clockwise'); command_widget('enc_cw', resolver, 'cw')
    ImGui.Text(ctx, 'Anticlockwise'); command_widget('enc_ccw', resolver, 'ccw')
  end
end

local function inspect_pad_mode(pm, compact)
  local l = cur_layout()
  ImGui.TextDisabled(ctx, string.format('Layout "%s", pad mode %d of %d', tostring(l and l.name), view.mode, #cur_modes()))
  text_field('pmname', 'Name', pm, 'name', -FLT_MIN)
  local pick = combo_ids('Kind##pm', M.PAD_MODE_KINDS, pm.kind, -FLT_MIN)
  if pick then push_undo(); set_pad_mode_kind(pm, pick); after_edit() end
  if pm.kind == 'mixer' then
    ImGui.Text(ctx, 'First track'); ImGui.SameLine(ctx)
    track_widget('pm_ft', pm, 'first_track')
    ImGui.TextDisabled(ctx, 'Pads 1-8 mute, 9-16 solo tracks ' .. ((pm.first_track or 0) + 1) .. '-' .. ((pm.first_track or 0) + 8))
  elseif pm.kind == 'free' then
    local ch, v = colour_combo('Colour##pm', pm.colour or 'white', false, -FLT_MIN)
    if ch then push_undo(); pm.colour = v; after_edit() end
  elseif pm.kind == 'drums' then
    ImGui.TextDisabled(ctx, 'Pads send drum hits to port 1 channel 10; velocity colours the pad.')
  elseif pm.kind == 'custom' and not compact then
    ImGui.TextDisabled(ctx, 'Click a pad on the panel to edit it.')
  end
end

local function inspect_pad(k)
  local pm = cur_mode()
  ImGui.SeparatorText(ctx, 'Pad ' .. k)
  if not pm then ImGui.Text(ctx, 'No pad mode'); return end
  inspect_pad_mode(pm, true)
  if pm.kind ~= 'custom' then
    ImGui.Spacing(ctx)
    ImGui.TextWrapped(ctx, 'Pad ' .. k .. ' here: ' .. select(3, pad_info(k)) .. '. Set the mode kind to Custom to give each pad its own function.')
    return
  end
  ImGui.Separator(ctx)
  pm.pads = pm.pads or {}
  if type(pm.pads[k]) ~= 'table' then pm.pads[k] = { kind = 'none' } end
  local p = pm.pads[k]
  local function resolver()
    local m = cur_mode()
    if not (m and m.pads) then return nil end
    return m.pads[k]
  end
  local pick = combo_ids('Function##pad', M.PAD_KINDS, p.kind or 'none', -FLT_MIN)
  if pick and pick ~= p.kind then
    push_undo()
    local keep = { kind = pick, colour = p.colour, on_colour = p.on_colour }
    if pick == 'action' then keep.command = p.command or 0
    elseif pick == 'transport' then keep.action = p.action or 'PlayStop'
    elseif pick == 'track_state' then keep.state = p.state or 'mute'; keep.track = p.track or 0 end
    set_table(p, keep)
    after_edit()
  end
  if p.kind == 'action' then
    command_widget('pad' .. k, resolver, 'command')
  elseif p.kind == 'transport' then
    local tp = combo_strings('Transport##pad', M.TRANSPORT_ACTIONS, p.action, -FLT_MIN)
    if tp then push_undo(); p.action = tp; after_edit() end
  elseif p.kind == 'track_state' then
    local sp = combo_strings('State##pad', M.TRACK_STATES, p.state, -FLT_MIN)
    if sp then push_undo(); p.state = sp; after_edit() end
    ImGui.Text(ctx, 'Track'); ImGui.SameLine(ctx)
    track_widget('pad_trk' .. k, p, 'track')
  end
  local ch, v = colour_combo('Colour##pad', p.colour, true, -FLT_MIN)
  if ch then push_undo(); p.colour = v; after_edit() end
  if p.kind and p.kind ~= 'none' then
    local ch2, v2 = colour_combo('On colour##pad', p.on_colour, true, -FLT_MIN)
    if ch2 then push_undo(); p.on_colour = v2; after_edit() end
    ImGui.TextDisabled(ctx, p.kind == 'action' and 'On colour: flash while the action is triggered (optional)' or 'On colour: shown while the state is active')
  end
end

local function inspect_bank()
  local b = cur_bank()
  ImGui.SeparatorText(ctx, string.format('Fader bank %d of %d', view.bank, #banks()))
  if not b then ImGui.Text(ctx, 'No bank'); return end
  if sel.sub == 'fader' then ImGui.TextDisabled(ctx, 'Fader ' .. sel.i .. ' in this bank: ' .. fader_text(b, sel.i))
  elseif sel.sub == 'knob' then ImGui.TextDisabled(ctx, 'Knob ' .. sel.i .. ' (' .. KNOB_FNS[view.knob_fn + 1] .. '): ' .. knob_text(b, sel.i, view.knob_fn))
  elseif sel.sub == 'fbtn' then ImGui.TextDisabled(ctx, 'Fader button ' .. sel.i .. ' (' .. FB_MODES[view.fb_mode + 1] .. '): ' .. fbtn_text(b, sel.i, view.fb_mode)) end
  text_field('bankname', 'Name', b, 'name', -FLT_MIN)
  local pick = combo_ids('Kind##bank', M.BANK_KINDS, b.kind, -FLT_MIN)
  if pick then
    push_undo(); b.kind = pick
    if pick == 'tracks' then b.first_track = b.first_track or 0 end
    after_edit()
  end
  if b.kind == 'tracks' then
    ImGui.Text(ctx, 'First track'); ImGui.SameLine(ctx)
    track_widget('bank_ft', b, 'first_track')
    ImGui.TextDisabled(ctx, 'Faders: volume of tracks ' .. ((b.first_track or 0) + 1) .. '-' .. ((b.first_track or 0) + 8) .. '; fader 9 is always master volume.')
  elseif b.kind == 'focused_fx' then
    ImGui.TextWrapped(ctx, 'Faders: focused FX parameters 1-8, knobs: 9-16. Fader buttons in Select mode: FX slots on/off of the selected track; in Mute mode: mute / solo / arm / FX bypass of the selected track.')
  end
end

local function inspect_layout()
  local l = cur_layout()
  ImGui.SeparatorText(ctx, 'Layout ' .. view.layout .. ' of ' .. #layouts())
  if not l then return end
  text_field('layname', 'Name', l, 'name', -FLT_MIN)
  push_id('layid')
  ImGui.SetNextItemWidth(ctx, -FLT_MIN)
  local rv, nid = ImGui.InputText(ctx, 'Id', tostring(l.id or ''), ImGui.InputTextFlags_EnterReturnsTrue)
  if rv then rename_layout_id(l.id, nid) end
  pop_id()
  ImGui.TextDisabled(ctx, 'Id is used as the key of per-layout combos (press Enter to rename)')
  local ch, v = colour_combo('Sweep colour##lay', l.sweep_colour or 'green', false, -FLT_MIN)
  if ch then push_undo(); l.sweep_colour = v; after_edit() end
  ImGui.TextDisabled(ctx, 'Colour of the pad sweep played when this layout becomes active')
  ImGui.Spacing(ctx)
  begin_disabled(#layouts() <= 1)
  if ImGui.Button(ctx, 'Delete this layout') then delete_layout() end
  end_disabled()
end

-- ---- external hold modifiers (foot switch etc.) ------------------------------------------------
local function unique_external_id()
  local mods = model.modifiers or {}
  local n = 1
  while mods['ext' .. n] ~= nil do n = n + 1 end
  return 'ext' .. n
end

local function add_external_modifier()
  push_undo()
  model.modifiers = model.modifiers or {}
  local id = unique_external_id()
  model.modifiers[id] = { external = { name = 'Foot switch', cc = 105, channel = M.EXTERNAL_CHANNEL, indicator = 'checkerboard' }, combos = {} }
  after_edit('Added external hold modifier ' .. id)
end

local function remove_external_modifier(id)
  if not is_external(id) then return end
  push_undo()
  model.modifiers[id] = nil
  if view.layer == id then view.layer = 'normal' end
  after_edit('Removed external hold modifier ' .. id)
end

local function draw_modifiers_panel()
  ImGui.SeparatorText(ctx, 'Modifiers')
  local ids = modifier_ids()
  local btn_names, n_ext = {}, 0
  for _, id in ipairs(ids) do
    if is_external(id) then n_ext = n_ext + 1 else btn_names[#btn_names + 1] = M.modifier_name(model, id) end
  end
  ImGui.TextWrapped(ctx, string.format('%d of at most 2 modifiers in use. Modifier buttons: %s (set a button to "Modifier latch" in the Normal layer). External hold modifiers: %d.',
    #ids, #btn_names > 0 and table.concat(btn_names, ', ') or 'none', n_ext))
  ImGui.TextDisabled(ctx, 'An external modifier is a CC from another device injected on MIDIIN3; combos fire while it is held (127 = held, 0 = released).')
  local to_remove
  for _, id in ipairs(ids) do
    if is_external(id) then
      local m = model.modifiers[id]
      local e = m.external
      push_id('ext_' .. id)
      ImGui.Separator(ctx)
      ImGui.TextDisabled(ctx, 'model.modifiers.' .. id)
      text_field('extname_' .. id, 'Name', e, 'name', -FLT_MIN)
      ImGui.SetNextItemWidth(ctx, 90)
      local cc = math.floor(tonumber(e.cc) or 0)
      local rv, nv = ImGui.InputInt(ctx, 'CC', cc, 1, 10)
      if rv and nv ~= cc then push_undo('extcc_' .. id); e.cc = math.max(0, math.min(127, nv)); after_edit() end
      ImGui.SameLine(ctx)
      ImGui.SetNextItemWidth(ctx, 90)
      local chn = math.floor(tonumber(e.channel) or M.EXTERNAL_CHANNEL)
      local rv2, nv2 = ImGui.InputInt(ctx, 'Channel', chn, 1, 1)
      if rv2 and nv2 ~= chn then push_undo('extch_' .. id); e.channel = math.max(0, math.min(15, nv2)); after_edit() end
      ImGui.SameLine(ctx); ImGui.TextDisabled(ctx, string.format('(0-based = MIDI ch %d)', chn + 1))
      local pick = combo_ids('Indicator', M.MODIFIER_INDICATORS, e.indicator or 'checkerboard', -FLT_MIN)
      if pick then push_undo(); e.indicator = pick; after_edit() end
      if ImGui.Button(ctx, 'Edit layer') then view.layer = id; view.follow = false; sel = { kind = nil } end
      ImGui.SetItemTooltip(ctx, 'Switch the Layer combo to this modifier, then click a control on the panel to set its combo')
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, 'Remove') then to_remove = id end
      pop_id()
    end
  end
  if to_remove then remove_external_modifier(to_remove) end
  ImGui.Separator(ctx)
  if ImGui.Button(ctx, 'Add external hold modifier') then add_external_modifier() end
  ImGui.SetItemTooltip(ctx, 'Adds model.modifiers.extN with CC 105 on channel 14 (0-based 13); edit the CC / channel to match the injecting unit')
  ImGui.Spacing(ctx)
end

-- ---- Exquis inspector --------------------------------------------------------------------------------
-- colour combo + dim checkbox shared by every Exquis control; `a` is the live assignment table
local function exquis_colour_dim(uid, a)
  local ch, v = exquis_colour_combo('Colour##xcol_' .. uid, a.colour, -FLT_MIN)
  if ch then push_undo(); a.colour = v; after_edit() end
  local rv, nd = ImGui.Checkbox(ctx, 'Dim##xdim_' .. uid, a.dim == true)
  if rv and nd ~= (a.dim == true) then push_undo(); a.dim = nd or nil; after_edit() end
  ImGui.SameLine(ctx); ImGui.TextDisabled(ctx, 'LED colour ((none) = unlit); dim = low brightness')
end

local function set_exquis_button_kind(a, kind)
  local keep = { kind = kind, colour = a.colour, dim = a.dim }
  if kind == 'builtin' then keep.builtin = a.builtin or 'transport_play'
  elseif kind == 'action' then keep.command = a.command or 0 end
  set_table(a, keep)
end

local function inspect_exquis_button(id, layer)
  local elem = EXQUIS_ELEM[id]
  if not elem then ImGui.Text(ctx, 'Unknown Exquis button ' .. tostring(id)); return end
  ImGui.SeparatorText(ctx, 'Exquis ' .. name_of(M.EXQUIS_BUTTONS, id) .. '  (CC ' .. elem .. ')')
  ImGui.TextDisabled(ctx, string.format('Mode "%s", %s layer: %s', tostring(cur_xmode().name or view.xmode), xlayer_name(layer), xpath(layer, 'buttons.' .. id)))
  if layer == 'shift' then
    ImGui.TextDisabled(ctx, 'Fires while the FCB1010 foot switch is held (shift CC ' .. tostring(exquis().shift_cc or 105) .. ')')
  end
  local uid = 'xbtn_' .. layer .. '_' .. id
  local function resolver()
    local t = xbuttons_of(layer)
    if type(t[id]) ~= 'table' then t[id] = { kind = 'none' } end
    return t[id]
  end
  local a = resolver()
  local kinds = { { 'none', 'Nothing' }, { 'builtin', 'Built-in' }, { 'action', 'Action' } }
  local cur = a.kind or 'none'
  for i, k in ipairs(kinds) do
    if ImGui.RadioButton(ctx, k[2] .. '##' .. uid, cur == k[1]) and cur ~= k[1] then
      push_undo(); set_exquis_button_kind(a, k[1]); after_edit()
    end
    if i < #kinds then ImGui.SameLine(ctx) end
  end
  if a.kind == 'builtin' then
    local pick = combo_ids('Function##xfn_' .. uid, M.EXQUIS_BUTTON_BUILTINS, a.builtin, -FLT_MIN)
    if pick then push_undo(); a.builtin = pick; after_edit() end
    if is_mode_step(a) then
      ImGui.TextWrapped(ctx, string.format('Steps through the %d Exquis mode(s) on the device (wrapping). LED: the mode colour ("Mode settings" in the top bar) unless a colour is chosen below.', #exquis().modes))
    end
  elseif a.kind == 'action' then
    command_widget(uid, resolver, 'command')
  elseif a.kind ~= nil and a.kind ~= 'none' then
    ImGui.TextColored(ctx, C.err, 'Unknown kind: ' .. tostring(a.kind))
  end
  exquis_colour_dim(uid, a)
end

local function inspect_exquis_encoder(i, layer)
  ImGui.SeparatorText(ctx, string.format('Exquis encoder %d  (CC %d)', i, EXQUIS_ENC_CC[i] or 0))
  ImGui.TextDisabled(ctx, string.format('Mode "%s", %s layer: %s', tostring(cur_xmode().name or view.xmode), xlayer_name(layer), xpath(layer, 'encoders[' .. i .. ']')))
  local uid = 'xenc_' .. layer .. '_' .. i
  local function resolver()
    local t = xencoders_of(layer)
    if type(t[i]) ~= 'table' then t[i] = { kind = 'none' } end
    return t[i]
  end
  local a = resolver()
  local pick = combo_ids('Kind##' .. uid, M.EXQUIS_ENCODER_KINDS, a.kind or 'none', -FLT_MIN)
  if pick and pick ~= a.kind then
    push_undo()
    local keep = { kind = pick, colour = a.colour, dim = a.dim }
    if pick == 'selected_send' or pick == 'fx_param' then keep.index = a.index or 0
    elseif pick == 'actions' then keep.cw = a.cw or 0; keep.ccw = a.ccw or 0 end
    set_table(a, keep)
    after_edit()
  end
  if a.kind == 'selected_send' or a.kind == 'fx_param' then
    push_id(uid .. '_idx')
    ImGui.SetNextItemWidth(ctx, 90)
    local cur = math.floor(tonumber(a.index) or 0) + 1
    local rv, nv = ImGui.InputInt(ctx, a.kind == 'selected_send' and 'Send number' or 'FX parameter number', cur, 1, 8)
    if rv and nv ~= cur then push_undo('xidx' .. uid); a.index = math.max(0, nv - 1); after_edit() end
    pop_id()
    ImGui.TextDisabled(ctx, a.kind == 'selected_send' and 'Send N of the selected track (shown 1-based; model.index is 0-based)'
                                                        or 'Parameter N of the focused FX (shown 1-based; model.index is 0-based)')
  elseif a.kind == 'actions' then
    ImGui.Text(ctx, 'Clockwise'); command_widget(uid .. '_cw', resolver, 'cw')
    ImGui.Text(ctx, 'Anticlockwise'); command_widget(uid .. '_ccw', resolver, 'ccw')
  end
  exquis_colour_dim(uid, a)
end

-- encoder pushes and slider zones: kind combo, action command or transport action, colour + dim
local function edit_exquis_trigger(uid, resolver, kinds)
  local a = resolver()
  local pick = combo_ids('Kind##' .. uid, kinds, a.kind or 'none', -FLT_MIN)
  if pick and pick ~= a.kind then
    push_undo()
    local keep = { kind = pick, colour = a.colour, dim = a.dim }
    if pick == 'action' then keep.command = a.command or 0
    elseif pick == 'transport' then keep.action = a.action or 'PlayStop' end
    set_table(a, keep)
    after_edit()
  end
  if a.kind == 'action' then
    command_widget(uid, resolver, 'command')
  elseif a.kind == 'transport' then
    local tp = combo_strings('Transport##' .. uid, M.TRANSPORT_ACTIONS, a.action or 'PlayStop', -FLT_MIN)
    if tp then push_undo(); a.action = tp; after_edit() end
    ImGui.TextDisabled(ctx, 'Toggle; the LED follows the transport state')
  elseif is_mode_step(a) then
    ImGui.TextWrapped(ctx, string.format('Steps through the %d Exquis mode(s) on the device (wrapping). LED: the mode colour ("Mode settings" in the top bar) unless a colour is chosen below.', #exquis().modes))
  end
  exquis_colour_dim(uid, a)
end

local function inspect_exquis_push(i)
  ImGui.SeparatorText(ctx, string.format('Exquis encoder %d push  (CC %d)', i, EXQUIS_PUSH_CC[i] or 0))
  ImGui.TextDisabled(ctx, string.format('Mode "%s": %s  (no shift layer)', tostring(cur_xmode().name or view.xmode), xpath('normal', 'pushes[' .. i .. ']')))
  edit_exquis_trigger('xpush_' .. i, function()
    local t = cur_xmode().pushes
    if type(t[i]) ~= 'table' then t[i] = { kind = 'none' } end
    return t[i]
  end, M.EXQUIS_PUSH_KINDS)
end

local function inspect_exquis_slider(k)
  ImGui.SeparatorText(ctx, string.format('Exquis slider zone %d  (CC %d)', k, EXQUIS_SLIDER_CC[k] or 0))
  if exquis().slider_mode ~= 'zones' then
    ImGui.TextWrapped(ctx, 'The slider is native (the keyboard\'s arpeggiator-rate slider) and its zones are not taken over. Choose "zones" in the Slider combo of the top bar to give the six zones REAPER functions.')
    return
  end
  ImGui.TextDisabled(ctx, string.format('Mode "%s": %s  (no shift layer)', tostring(cur_xmode().name or view.xmode), xpath('normal', 'slider[' .. k .. ']')))
  edit_exquis_trigger('xsl_' .. k, function()
    local t = cur_xmode().slider
    if type(t[k]) ~= 'table' then t[k] = { kind = 'none' } end
    return t[k]
  end, M.EXQUIS_SLIDER_KINDS)
end

-- live keyboard box: device queries, start-up snapshot file, root / scale (device settings, not the model)
local function draw_exquis_keyboard_box()
  push_id('xqkb')
  ImGui.SeparatorText(ctx, 'Keyboard  (live Exquis settings, not part of the model)')
  if not xq.out then ImGui.TextColored(ctx, C.err, 'MIDI output "Exquis" not found: enable it in Preferences > MIDI Devices')
  elseif not xq.has_in then ImGui.TextColored(ctx, C.err, 'MIDI input "Exquis" not found: replies cannot arrive') end
  if ImGui.Button(ctx, 'Read from keyboard') then XQ.read_from_keyboard() end
  ImGui.SetItemTooltip(ctx, 'Query the current layout snapshot (cmd 09), root note (06) and scale (07)')
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Capture snapshot for start-up') then XQ.capture_snapshot() end
  ImGui.SetItemTooltip(ctx, 'Query the snapshot and write ' .. XQ.SNAPSHOT_PATH .. '\nApply embeds it, and the ReaLearn unit restores this layout each time it loads')
  begin_disabled(xq.snap_file == nil)
  if ImGui.Button(ctx, 'Clear snapshot') then XQ.clear_snapshot_file() end
  end_disabled()
  ImGui.SetItemTooltip(ctx, 'Delete the snapshot file (Apply then writes a preset without a start-up layout)')
  ImGui.SameLine(ctx)
  begin_disabled(not ((xq.snap_file and xq.snap_file.bytes == 255) or (xq.snapshot and #xq.snapshot == 255)))
  if ImGui.Button(ctx, 'Restore now') then XQ.restore_snapshot() end
  end_disabled()
  ImGui.SetItemTooltip(ctx, 'Send the stored snapshot to the keyboard immediately (e.g. after the Exquis app put it back to its own layout)')
  if xq.pending then ImGui.TextColored(ctx, C.live, 'waiting for the ' .. xq.pending .. ' reply...') end
  if xq.snap_file then
    ImGui.TextColored(ctx, C.ok, string.format('Snapshot file: %s (%d bytes)', xq.snap_file.comment ~= '' and xq.snap_file.comment or 'no comment', xq.snap_file.bytes))
  else
    ImGui.TextDisabled(ctx, 'Snapshot file: none (no start-up layout is embedded on Apply)')
  end

  -- layout identification
  local _, head, note = XQ.display()
  ImGui.Text(ctx, head); ImGui.SameLine(ctx); ImGui.TextDisabled(ctx, '(' .. note .. ')')
  if ImGui.SmallButton(ctx, 'Rescan') then
    local n = #XQ.scan_layouts()
    XQ.identify()
    status.text, status.col = string.format('%d layout file(s) in %s', n, XQ.LAYOUT_DIR), nil
  end
  ImGui.SetItemTooltip(ctx, 'Reload the .xqilayout files from ' .. XQ.LAYOUT_DIR)
  ImGui.SameLine(ctx)
  if not xq.layouts then XQ.scan_layouts() end
  local items = { { id = '', name = xq.keys and '(keyboard snapshot)' or '(none)' } }
  for _, l in ipairs(xq.layouts) do
    items[#items + 1] = { id = l.file, name = l.name .. ((l.title and l.title ~= l.name) and ('  (' .. l.title .. ')') or '') }
  end
  begin_disabled(xq.keys ~= nil)
  local pick = combo_ids('Show file##xqpick', items, xq.pick or '', -FLT_MIN)
  if pick then xq.pick = pick ~= '' and pick or nil end
  end_disabled()
  if xq.keys then ImGui.TextDisabled(ctx, 'The key field shows the snapshot read from the keyboard; a file can only be displayed before a snapshot is read.')
  else ImGui.TextDisabled(ctx, 'Nothing read from the keyboard yet: pick a file to display its notes and colours.') end

  -- root / scale
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, 'Root'); ImGui.SameLine(ctx)
  local rp = combo_ids('##xqroot', XQ.ROOT_ITEMS, xq.ui_root, 70)
  if rp then xq.ui_root = rp end
  ImGui.SameLine(ctx); ImGui.Text(ctx, 'Scale'); ImGui.SameLine(ctx)
  local sp = combo_ids('##xqscale', XQ.SCALE_ITEMS, xq.ui_scale, 150)
  if sp then xq.ui_scale = sp end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Send to keyboard') then XQ.send_root_scale() end
  ImGui.SetItemTooltip(ctx, 'Send 06 <root> and 07 <scale> to the Exquis (Developer Mode)')
  if xq.root then
    ImGui.TextDisabled(ctx, string.format('Device: root %s, scale %s', XQ.ROOTS[xq.root + 1], XQ.SCALES[(xq.scale or 0) + 1]))
  else
    ImGui.TextDisabled(ctx, 'Device root / scale not read yet')
  end
  pop_id()
  ImGui.Spacing(ctx)
end

local function draw_exquis_inspector()
  local layer = view.xlayer
  draw_exquis_keyboard_box()
  -- "Mode settings" (top bar toggle): name and colour of the mode being edited
  if view.show_xmode then
    local x, m = exquis(), cur_xmode()
    push_id('xmodeset')
    ImGui.SeparatorText(ctx, string.format('Exquis mode %d of %d', view.xmode, #x.modes))
    ImGui.TextDisabled(ctx, 'model.exquis.modes[' .. view.xmode .. ']')
    text_field('xmname', 'Name', m, 'name', -FLT_MIN)
    local ch, v = exquis_colour_combo('Colour##xmcol', m.colour or 'white', -FLT_MIN)
    if ch then push_undo(); m.colour = v; after_edit() end
    ImGui.TextDisabled(ctx, 'Mode colour: LED of every button / push set to "Next / Previous Exquis mode" ((none) = white)')
    ImGui.TextWrapped(ctx, 'Each mode is a full set of assignments (buttons, encoders, pushes, slider, shift layer). A button set to "Next Exquis mode" (Built-in) or an encoder push set to it steps through the modes on the device, wrapping around. "+" in the top bar adds a copy of this mode.')
    begin_disabled(#x.modes <= 1)
    if ImGui.Button(ctx, 'Remove this mode') then remove_xmode() end
    end_disabled()
    pop_id()
    ImGui.Spacing(ctx)
  end
  if sel.dev == 'exquis' and sel.kind == 'button' then inspect_exquis_button(sel.id, layer)
  elseif sel.dev == 'exquis' and sel.kind == 'encoder' then inspect_exquis_encoder(sel.id, layer)
  elseif sel.dev == 'exquis' and sel.kind == 'push' then inspect_exquis_push(sel.id)
  elseif sel.dev == 'exquis' and sel.kind == 'slider' then inspect_exquis_slider(sel.id)
  else
    ImGui.SeparatorText(ctx, 'Exquis inspector')
    ImGui.TextWrapped(ctx, 'Click a control on the Exquis panel to edit it: the four encoders (ring = turn, centre or the "Push" line = push), the six slider zones, and the eight buttons. The pads stay native MPE and are not remapped.')
    ImGui.Spacing(ctx)
    ImGui.TextWrapped(ctx, 'The Mode combo picks which Exquis mode (model.exquis.modes[N], a full set of assignments) is edited; a button or push set to "Next / Previous Exquis mode" steps through them on the device. The Layer combo switches between the normal assignments and the shift layer (modes[N].shift), active while the FCB1010 foot switch is held. Only buttons and encoder turns have a shift layer. Ctrl+Z / Ctrl+Y undo and redo.')
  end
end

local function draw_inspector()
  if view.device == 'exquis' then
    draw_exquis_inspector()
  else
    if view.show_modifiers then draw_modifiers_panel() end
    if sel.kind == 'button' then inspect_button(sel.id)
    elseif sel.kind == 'encoder' then inspect_encoder()
    elseif sel.kind == 'pad' then inspect_pad(sel.k)
    elseif sel.kind == 'bank' then inspect_bank()
    elseif sel.kind == 'layout' then inspect_layout()
    elseif sel.kind == 'padmode' then
      ImGui.SeparatorText(ctx, 'Pad mode')
      local pm = cur_mode()
      if pm then inspect_pad_mode(pm, false) end
    else
      ImGui.SeparatorText(ctx, 'Inspector')
      ImGui.TextWrapped(ctx, 'Click a control on the panel to edit it: transport and bank buttons, the Back / DAW buttons, the encoder (ring = turn, centre = press), pads, faders, knobs, fader buttons and the side buttons next to the pads.')
      ImGui.Spacing(ctx)
      ImGui.TextWrapped(ctx, 'The Layer combo switches between the normal assignments and what each modifier (a latched button, or an external hold modifier such as a foot switch) gives the other buttons. "Modifiers..." in the top bar manages external modifiers. Ctrl+Z / Ctrl+Y undo and redo.')
    end
  end
  ImGui.Spacing(ctx); ImGui.Separator(ctx)
  ImGui.TextDisabled(ctx, string.format('%d undo steps  |  model: %s', #undo_stack, apply.MODEL_PATH))
end

-- ================================================================================================
-- 10. Frame and main loop
-- ================================================================================================
local function follow_live()
  local nmodes = #cur_modes()
  local xm = model.exquis   -- Exquis mode count (only when the section exists; never created from here)
  local nx = (type(xm) == 'table' and type(xm.modes) == 'table' and #xm.modes > 0) and #xm.modes or 1
  live = state.read({ bank = #banks(), mode = 5, knob = 4, pad = math.max(1, nmodes), layout = #layouts(), modifiers = modifier_ids(), xmode = nx })
  if not live then return end
  -- the unit's state is tracked from the presses it echoes; until the first press it is unknown
  if not live.synced then return end
  -- the Exquis echoes its mode presses (CC 90 / 91 on port 1); shown only while the Exquis view is active
  if view.device == 'exquis' and type(live.xmode) == 'number' then view.xmode = math.max(1, math.min(nx, math.floor(live.xmode) + 1)) end
  if live.layout then view.layout = live.layout + 1 end
  if live.pad then view.mode = live.pad + 1 end
  if live.bank then view.bank = live.bank + 1 end
  if live.mode then view.fb_mode = math.max(0, math.min(4, live.mode)) end
  if live.knob then view.knob_fn = math.max(0, math.min(3, live.knob)) end
  local layer = 'normal'
  for _, mid in ipairs(modifier_ids()) do if live['mod_' .. mid] == 1 then layer = mid end end
  view.layer = layer
end

local function frame()
  picker_poll()
  XQ.refresh()
  XQ.poll()
  if not ImGui.IsAnyItemActive(ctx) then
    if ImGui.IsKeyChordPressed(ctx, ImGui.Mod_Ctrl | ImGui.Key_Z) then undo() end
    if ImGui.IsKeyChordPressed(ctx, ImGui.Mod_Ctrl | ImGui.Key_Y) then redo() end
  end
  clamp_view()
  if view.follow then follow_live() else live = nil end
  clamp_view()
  draw_topbar()
  ImGui.Separator(ctx)
  local avail_w = ImGui.GetContentRegionAvail(ctx)
  local insp_w = math.max(360, math.min(560, avail_w * 0.38))
  if begin_child('panel', avail_w - insp_w - 8, 0, ImGui.ChildFlags_Borders, ImGui.WindowFlags_HorizontalScrollbar) then
    if view.device == 'exquis' then draw_exquis_panel() else draw_panel() end
    end_child()
  end
  ImGui.SameLine(ctx)
  if begin_child('inspector', 0, 0, ImGui.ChildFlags_Borders) then
    push_wrap()
    draw_inspector()
    pop_wrap()
    end_child()
  end
end

local function ensure_context()
  if ImGui.ValidatePtr(ctx, 'ImGui_Context*') then return end
  -- ReaImGui collects a context that missed a defer cycle (e.g. after a long Apply); build a fresh one
  ctx = ImGui.CreateContext('MIDI Control Center')
  font = ImGui.CreateFont('sans-serif', ImGui.FontFlags_None)
  ImGui.Attach(ctx, font)
end

local function loop()
  if pending_apply then
    pending_apply = false
    local ok, err = pcall(do_apply)
    if not ok then status.text, status.col = 'Apply failed: ' .. tostring(err), C.err; apply_running = false end
  end
  ensure_context()
  if pending_dock then ImGui.SetNextWindowDockID(ctx, pending_dock); pending_dock = nil end
  ImGui.SetNextWindowSize(ctx, 1500, 760, ImGui.Cond_FirstUseEver)
  ImGui.PushFont(ctx, font, 13)
  local visible, open = ImGui.Begin(ctx, 'MIDI Control Center', true)
  if visible then
    reaper.SetExtState(EXT, 'dock', tostring(ImGui.GetWindowDockID(ctx)), true)
    local ok, err = pcall(frame)
    if not ok then
      last_error = tostring(err)
      unwind()
      -- show the failure instead of a blank window, and switch Follow off since it is the usual trigger
      if ImGui.ValidatePtr(ctx, 'ImGui_Context*') then
        ImGui.TextColored(ctx, 0xFF6060FF, 'Editor error (this frame was abandoned): ' .. last_error)
        ImGui.Text(ctx, 'Follow keyboard has been switched off. Please report the line above.')
      end
      view.follow = false
    end
    -- ReaImGui may have collected the context during the frame (a call inside it pumped messages); never
    -- call End/PopFont on a dead context, just rebuild it next cycle
    if ImGui.ValidatePtr(ctx, 'ImGui_Context*') then
      ImGui.End(ctx)
      ImGui.PopFont(ctx)
    else
      last_error = 'ImGui context was lost during the frame (rebuilt); last action: ' .. tostring(last_action)
    end
  elseif ImGui.ValidatePtr(ctx, 'ImGui_Context*') then
    ImGui.PopFont(ctx)
  end
  if pending_picker then picker_open_now() end
  if open then reaper.defer(loop) end
end

reaper.defer(loop)

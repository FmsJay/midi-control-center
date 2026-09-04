-- @description Oxygen Pro 61 Editor
-- @version 1.0
-- @author Oxygen Pro 61 integration
-- @about
--   ReaImGui editor for the Oxygen Pro 61 ReaLearn layout model. Draws the keyboard panel, lets you
--   click any control to edit what it does, and applies the generated preset to the running ReaLearn.
--   Needs ReaImGui 0.10 and the modules in ./oxygen_editor (model, generator, apply, state, json).
-- @provides [main] .

-- ================================================================================================
-- 0. Guards, modules, ImGui context
-- ================================================================================================
if not reaper or not reaper.APIExists or not reaper.APIExists('ImGui_GetBuiltinPath') then
  reaper.MB('This script needs ReaImGui (install it via ReaPack).', 'Oxygen Pro 61 Editor', 0)
  return
end

local SCRIPT_PATH = debug.getinfo(1, 'S').source:sub(2)
local DIR = (SCRIPT_PATH:match('^(.*)[/\\]') or '.') .. '/oxygen_editor'
package.path = DIR .. '/?.lua;' .. package.path .. ';' .. reaper.ImGui_GetBuiltinPath() .. '/?.lua'

local ImGui = require 'imgui' '0.10'
local M     = require 'model'
local apply = require 'apply'
local state = require 'state'

local ctx  = ImGui.CreateContext('Oxygen Pro 61 Editor')
local font = ImGui.CreateFont('sans-serif', ImGui.FontFlags_None)
ImGui.Attach(ctx, font)
local FLT_MIN = ImGui.NumericLimits_Float()

local EXT = 'OxygenPro61Editor'

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

-- ================================================================================================
-- 2. State
-- ================================================================================================
local model, model_source = apply.load_model()
local errors = M.validate(model)
local status = { text = 'Loaded ' .. tostring(model_source), col = nil }
local undo_stack, redo_stack = {}, {}
local UNDO_MAX = 60
local last_undo = { key = nil, t = 0 }
local sel  = { kind = nil }      -- button{id} | encoder | pad{k} | bank{sub,i} | layout | padmode
local view = { layout = 1, mode = 1, bank = 1, layer = 'normal', follow = false, fb_mode = 0, knob_fn = 0,
               zoom = tonumber(reaper.GetExtState(EXT, 'zoom')) or 1.0,
               show_modifiers = false }   -- "Modifiers..." management section at the top of the inspector
local live = nil                 -- last state.read()
local picker = { active = false, uid = nil, resolver = nil, field = nil }
local last_error = nil
local pending_apply, apply_running = false, false
local pending_dock = tonumber(reaper.GetExtState(EXT, 'dock'))
if pending_dock == 0 then pending_dock = nil end
local name_cache = {}
local stk = { child = 0, combo = 0, col = 0, id = 0, disabled = 0 }   -- open Begin*/Push* for error recovery

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
local function picker_start(uid, resolver, field)
  if picker.active then reaper.PromptForAction(-1, 0, 0) end
  reaper.PromptForAction(1, 0, 0)
  picker.active, picker.uid, picker.resolver, picker.field = true, uid, resolver, field
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
local function begin_disabled(d) ImGui.BeginDisabled(ctx, d); stk.disabled = stk.disabled + 1 end
local function end_disabled() ImGui.EndDisabled(ctx); stk.disabled = stk.disabled - 1 end

-- after a pcall failure inside the frame, close whatever is still open so the next frame is clean
local function unwind()
  while stk.combo > 0 do ImGui.EndCombo(ctx); stk.combo = stk.combo - 1 end
  while stk.disabled > 0 do ImGui.EndDisabled(ctx); stk.disabled = stk.disabled - 1 end
  while stk.id > 0 do ImGui.PopID(ctx); stk.id = stk.id - 1 end
  if stk.col > 0 then ImGui.PopStyleColor(ctx, stk.col); stk.col = 0 end
  while stk.child > 0 do ImGui.EndChild(ctx); stk.child = stk.child - 1 end
end

-- combo over {id,name} items; returns the newly chosen id or nil
local function combo_ids(label, items, cur, width)
  if width then ImGui.SetNextItemWidth(ctx, width) end
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
  if width then ImGui.SetNextItemWidth(ctx, width) end
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
  after_edit('Reloaded ' .. tostring(src))
end
local function do_reset()
  push_undo()
  model = M.default()
  after_edit('Reset to the shipped default layout')
end

local function draw_topbar()
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
  if view.show_modifiers then push_col(ImGui.Col_Button, 0x4A6FA5FF); push_col(ImGui.Col_ButtonHovered, 0x5A80B8FF); push_col(ImGui.Col_ButtonActive, 0x3A5F95FF) end
  if ImGui.Button(ctx, 'Modifiers...') then view.show_modifiers = not view.show_modifiers end
  if view.show_modifiers then pop_col(3) end
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

  if ImGui.Button(ctx, 'Apply') and not apply_running then apply_running = true; pending_apply = true end
  ImGui.SetItemTooltip(ctx, 'Generate the preset, back up the current one, write it and reload ReaLearn')
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Save') then do_save() end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Reload') then do_reload() end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Reset to default') then do_reset() end
  ImGui.SameLine(ctx)
  ImGui.SameLine(ctx)
  begin_disabled(#undo_stack == 0)
  if ImGui.Button(ctx, 'Undo') then undo() end
  end_disabled()
  ImGui.SameLine(ctx)
  begin_disabled(#redo_stack == 0)
  if ImGui.Button(ctx, 'Redo') then redo() end
  end_disabled()
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, ImGui.IsWindowDocked(ctx) and 'Undock' or 'Dock') then
    pending_dock = ImGui.IsWindowDocked(ctx) and 0 or -1
  end

  -- status line + validation
  if status.col then ImGui.TextColored(ctx, status.col, status.text) else ImGui.Text(ctx, status.text) end
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
  if sel.kind ~= kind then return false end
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
  if sel.kind == 'encoder' then ImGui.DrawList_AddCircle(G.dl, X(ecx), Y(ecy), (r + 2) * G.z, C.sel, 0, 2) end
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

local function draw_inspector()
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
  ImGui.Spacing(ctx); ImGui.Separator(ctx)
  ImGui.TextDisabled(ctx, string.format('%d undo steps  |  model: %s', #undo_stack, apply.MODEL_PATH))
end

-- ================================================================================================
-- 10. Frame and main loop
-- ================================================================================================
local function follow_live()
  local nmodes = #cur_modes()
  live = state.read({ bank = #banks(), mode = 5, knob = 4, pad = math.max(1, nmodes), layout = #layouts(), modifiers = modifier_ids() })
  if not live then return end
  -- the unit's state is tracked from the presses it echoes; until the first press it is unknown
  if not live.synced then return end
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
  local insp_w = math.max(300, math.min(420, avail_w * 0.32))
  if begin_child('panel', avail_w - insp_w - 8, 0, ImGui.ChildFlags_Borders, ImGui.WindowFlags_HorizontalScrollbar) then
    draw_panel()
    end_child()
  end
  ImGui.SameLine(ctx)
  if begin_child('inspector', 0, 0, ImGui.ChildFlags_Borders) then
    draw_inspector()
    end_child()
  end
end

local function ensure_context()
  if ImGui.ValidatePtr(ctx, 'ImGui_Context*') then return end
  -- ReaImGui collects a context that missed a defer cycle (e.g. after a long Apply); build a fresh one
  ctx = ImGui.CreateContext('Oxygen Pro 61 Editor')
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
  local visible, open = ImGui.Begin(ctx, 'Oxygen Pro 61 Editor', true)
  if visible then
    reaper.SetExtState(EXT, 'dock', tostring(ImGui.GetWindowDockID(ctx)), true)
    local ok, err = pcall(frame)
    if not ok then
      last_error = tostring(err)
      unwind()
    end
    ImGui.End(ctx)
  end
  ImGui.PopFont(ctx)
  if open then reaper.defer(loop) end
end

reaper.defer(loop)

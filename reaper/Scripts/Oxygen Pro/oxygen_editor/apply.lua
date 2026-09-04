-- Oxygen Pro 61 editor: write the generated preset into REAPER and make ReaLearn pick it up.
-- REAPER-only (uses the reaper API). Every apply writes live.preset.<timestamp>.bak next to the preset before
-- replacing it, so any earlier state can be copied back by hand; "Reset to default" + Apply restores the shipped layout.

local A = {}

local function this_dir()
    local src = debug.getinfo(1, "S").source:sub(2)
    return src:match("^(.*)[/\\]") or "."
end
A.DIR = this_dir()
package.path = A.DIR .. "/?.lua;" .. package.path
local generator = require("generator")
local model_mod = require("model")

local res = reaper.GetResourcePath()
A.PRESET_DIR  = res .. "/Data/helgoboss/realearn/presets/main/oxygen-pro-61"
A.PRESET      = A.PRESET_DIR .. "/live.preset.luau"
A.MODEL_PATH  = A.DIR .. "/model.json"
A.EXQUIS_DIR  = res .. "/Data/helgoboss/realearn/presets/main/exquis"
A.EXQUIS_PRESET = A.EXQUIS_DIR .. "/main.preset.luau"
A.HELGOBOX_NAME = "Helgobox - ReaLearn & Playtime"
A.RESYNC_CMD  = "_REALEARN_SEND_ALL_FEEDBACK"

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end
local function write_file(path, s)
    local f, err = io.open(path, "wb")
    if not f then return nil, err end
    f:write(s); f:close()
    return true
end
local function file_exists(path)
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

-- the Helgobox instance in the monitoring FX chain (where the auto units live)
function A.find_helgobox()
    local master = reaper.GetMasterTrack(0)
    local n = reaper.TrackFX_GetRecCount(master)
    for i = 0, n - 1 do
        local ok, name = reaper.TrackFX_GetFXName(master, 0x1000000 + i, "")
        if ok and name:find("Helgobox", 1, true) then return master, 0x1000000 + i end
    end
    return nil
end

-- Ask the running ReaLearn instance to re-read its state. REAPER's "vst_chunk" round trip makes the plug-in
-- restore from its own state; ReaLearn then resolves the linked preset id from disk. Returns true if it ran.
function A.reload_instance()
    local track, fx = A.find_helgobox()
    if not track then return false, "Helgobox not found in the monitoring FX chain" end
    local ok, chunk = reaper.TrackFX_GetNamedConfigParm(track, fx, "vst_chunk")
    if not ok or not chunk or chunk == "" then return false, "could not read the Helgobox state chunk" end
    local set_ok = reaper.TrackFX_SetNamedConfigParm(track, fx, "vst_chunk", chunk)
    if not set_ok then return false, "REAPER refused to set the Helgobox state chunk" end
    return true
end

function A.send_all_feedback()
    local cmd = reaper.NamedCommandLookup(A.RESYNC_CMD)
    if cmd ~= 0 then reaper.Main_OnCommand(cmd, 0); return true end
    return false
end

-- current device number of the port-1 input (for drum injection / watcher echoes)
function A.port1_device()
    for i = 0, reaper.GetNumMIDIInputs() - 1 do
        local ok, name = reaper.GetMIDIInputNameNoAlias(i, "")
        if ok and name == "Oxygen Pro 61" then return i end
    end
    return nil
end

-- Generate, back up, write, reload. Returns ok, human-readable message.
function A.apply(model, opts)
    opts = opts or {}
    local errors = model_mod.validate(model)
    if #errors > 0 then return false, "model is not valid: " .. errors[1] end
    local dev = A.port1_device()
    if dev then model.port1_input_device = dev end
    local text = generator.generate(model, { author = opts.author or "Oxygen Pro 61 editor" })
    -- self-check: the generated text must load and return a preset table
    local preset, err = generator.evaluate(text)
    if not preset then return false, "generated preset does not run: " .. tostring(err) end
    local current = read_file(A.PRESET)
    if current then write_file(A.PRESET_DIR .. "/live.preset." .. os.date("%Y%m%d-%H%M%S") .. ".bak", current) end
    local ok, werr = write_file(A.PRESET, text)
    if not ok then return false, "could not write " .. A.PRESET .. ": " .. tostring(werr) end
    model_mod.save(model, A.MODEL_PATH)
    local exquis_note = ""
    local xtext = generator.generate_exquis(model, { author = opts.author or "Oxygen Pro 61 editor" })
    if xtext then
        local xpreset, xerr = generator.evaluate(xtext)
        if not xpreset then return false, "generated Exquis preset does not run: " .. tostring(xerr) end
        reaper.RecursiveCreateDirectory(A.EXQUIS_DIR, 0)
        local xcur = read_file(A.EXQUIS_PRESET)
        if xcur then write_file(A.EXQUIS_DIR .. "/main.preset." .. os.date("%Y%m%d-%H%M%S") .. ".bak", xcur) end
        write_file(A.EXQUIS_PRESET, xtext)
        exquis_note = string.format(" + Exquis %d mappings", #xpreset.mappings)
    end
    local rl_ok, rl_err = A.reload_instance()
    A.send_all_feedback()
    local msg = string.format("wrote %d mappings to live.preset.luau", #preset.mappings) .. exquis_note
    if rl_ok then msg = msg .. "; ReaLearn reloaded" else msg = msg .. "; restart REAPER to load it (" .. tostring(rl_err) .. ")" end
    return true, msg, rl_ok
end

function A.load_model()
    if file_exists(A.MODEL_PATH) then
        local m, err = model_mod.load(A.MODEL_PATH)
        if m then return m, "model.json" end
        return model_mod.default(), "model.json unreadable (" .. tostring(err) .. "), using default"
    end
    return model_mod.default(), "default (hand-built layout)"
end

return A

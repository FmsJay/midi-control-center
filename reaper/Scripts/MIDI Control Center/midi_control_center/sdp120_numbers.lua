-- SDP-120 number entry, watcher side. The ReaLearn unit turns a typed tone number (program change on channel 1)
-- into "CC echo_cc on channel echo_channel + 1" injected into the piano's own input; this module reads the
-- model, matches that echo, and performs the assigned entry (REAPER action / add an FX to a track).
-- Loaded by "Oxygen Pro - Live watcher.lua"; reloads the model whenever apply bumps the ExtState generation.
local S = {}

local function this_dir()
    local src = debug.getinfo(1, "S").source:sub(2)
    return src:match("^(.*)[/\\]") or "."
end
S.DIR = this_dir()
package.path = S.DIR .. "/?.lua;" .. package.path
local json = require("json")

S.MODEL_PATH = S.DIR .. "/model.json"
S.GEN_KEY, S.GEN_FIELD = "MidiControlCenter", "model_gen"
S.cfg = nil            -- the model's sdp120 section, or nil when disabled / absent
S.gen = nil
S.log = function(s) reaper.ShowConsoleMsg("[sdp120] " .. s .. "\n") end

function S.load()
    S.gen = reaper.GetExtState(S.GEN_KEY, S.GEN_FIELD)
    local f = io.open(S.MODEL_PATH, "r")
    if not f then S.cfg = nil; return false, "no model.json" end
    local text = f:read("*a"); f:close()
    local ok, model = pcall(json.decode, text)
    if not ok or type(model) ~= "table" then S.cfg = nil; return false, "model.json unreadable" end
    local x = model.sdp120
    if type(x) ~= "table" or not x.enabled then S.cfg = nil; return false, "sdp120 disabled" end
    S.cfg = x
    S.status = 0xB0 + (tonumber(x.echo_channel) or 13)
    S.cc = tonumber(x.echo_cc) or 20
    S.by_number = {}
    for _, e in ipairs(x.numbers or {}) do
        if type(e) == "table" and tonumber(e.number) then S.by_number[math.floor(tonumber(e.number))] = e end
    end
    return true
end

function S.reload_if_changed()
    if reaper.GetExtState(S.GEN_KEY, S.GEN_FIELD) ~= S.gen then S.load() end
end

local function target_track(kind)
    if kind == "new" then
        reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
        local tr = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
        reaper.SetOnlyTrackSelected(tr)
        return tr
    elseif kind == "first" then
        return reaper.GetTrack(0, 0)
    end
    return reaper.GetSelectedTrack(0, 0) or reaper.GetTrack(0, 0)
end

local function run_command(cmd)
    local id = type(cmd) == "number" and cmd or reaper.NamedCommandLookup(tostring(cmd))
    if not id or id == 0 then return false, "unknown command " .. tostring(cmd) end
    reaper.Main_OnCommand(id, 0)
    return true
end

-- perform one entry; returns ok, message
function S.execute(entry)
    if type(entry) ~= "table" or entry.kind == nil or entry.kind == "none" then return false, "nothing assigned" end
    if entry.kind == "action" then
        return run_command(entry.command)
    elseif entry.kind == "fx" then
        local tr = target_track(entry.track)
        if not tr then return false, "no track to add the FX to" end
        reaper.Undo_BeginBlock()
        local idx = reaper.TrackFX_AddByName(tr, tostring(entry.fx), false, entry.reuse and 1 or -1)
        reaper.Undo_EndBlock("SDP-120: add " .. tostring(entry.fx), -1)
        if idx < 0 then return false, "FX not found: " .. tostring(entry.fx) end
        if entry.show ~= false then reaper.TrackFX_Show(tr, idx, 3) end
        return true, "added " .. tostring(entry.fx)
    end
    return false, "unknown kind " .. tostring(entry.kind)
end

-- called by the watcher for every 3-byte input event; returns true when it was the number echo
function S.handle(status, d1, d2)
    if not S.cfg or status ~= S.status or d1 ~= S.cc then return false end
    local number = d2 + 1
    local entry = S.by_number[number]
    if not entry then S.log(string.format("number %03d: nothing assigned", number)); return true end
    local ok, msg = S.execute(entry)
    S.log(string.format("number %03d: %s", number, msg or (ok and "done" or "failed")))
    return true
end

return S

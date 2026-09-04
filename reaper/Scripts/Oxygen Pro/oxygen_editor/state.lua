-- Oxygen Pro 61 editor: live state of the running ReaLearn unit.
--
-- The unit is an "auto unit" created from controllers.json, so its compartment parameters are NOT the FX
-- parameters of the Helgobox instance (those belong to the instance's own main unit and read "Main p1"...).
-- Instead the generated preset echoes every state-changing press into the port-1 input as a CC on channel 1,
-- exactly as it already does for the Live watcher, and this module replays those echoes with the same
-- clamp / wrap rules the preset uses:
--   B0 39..3D 7F  Mode button Off/Rec/Select/Mute/Solo    B0 55/56/57/53 7F  knob function Pan/Device/Send1/SelSends
--   B0 6E / 6F 7F bank - / +  (clamped)                    B0 6B / 6C 7F  pad mode - / + (wraps)
--   B0 71 7F      layout toggle (wraps)                     B0 68 7F / 00  modifier layer armed / dropped
-- The state is unknown until the first echo arrives (`synced` = false); the editor shows it as such.

local S = {}
local st = { bank = 0, mode = 0, knob = 0, pad = 0, layout = 0, mod = false, synced = false, last_event = nil }
local counts = { bank = 4, pad = 5, layout = 2 }
local last_seq = nil

local MODE_CC = { [0x39] = 0, [0x3A] = 1, [0x3B] = 2, [0x3C] = 3, [0x3D] = 4 }
local KNOB_CC = { [0x55] = 0, [0x56] = 1, [0x57] = 2, [0x53] = 3 }

function S.set_counts(c)
    if c then for k, v in pairs(c) do if v and v > 0 then counts[k] = v end end end
end

local function handle(cc, val)
    if MODE_CC[cc] and val > 0 then st.mode = MODE_CC[cc]
    elseif KNOB_CC[cc] and val > 0 then st.knob = KNOB_CC[cc]
    elseif cc == 0x6E and val > 0 then st.bank = math.max(0, st.bank - 1)
    elseif cc == 0x6F and val > 0 then st.bank = math.min(counts.bank - 1, st.bank + 1)
    elseif cc == 0x6B and val > 0 then st.pad = (st.pad - 1) % counts.pad
    elseif cc == 0x6C and val > 0 then st.pad = (st.pad + 1) % counts.pad
    elseif cc == 0x71 and val > 0 then st.layout = (st.layout + 1) % counts.layout
    elseif cc == 0x68 then st.mod = val > 0
    else return false end
    st.synced = true
    st.last_event = reaper.time_precise()
    return true
end

-- call every frame; consumes new port-1 echoes from REAPER's recent-input buffer
function S.poll()
    local newest
    for i = 0, 63 do
        local seq, buf = reaper.MIDI_GetRecentInputEvent(i)
        if not seq or seq == 0 or not buf or buf == "" then break end
        if last_seq and seq <= last_seq then break end
        if newest == nil then newest = seq end
        if last_seq and #buf >= 3 then
            local status, d1, d2 = buf:byte(1, 3)
            if status == 0xB0 then handle(d1, d2) end
        end
    end
    if newest then last_seq = newest end
    if last_seq == nil then last_seq = 0 end
end

-- returns the tracked state (0-based indices); `synced` tells whether any echo has been seen yet
-- `c.modifiers` may list modifier ids; the checkerboard echo (CC 104) is shared by every modifier, so all of them
-- report the same held/armed flag (at most two exist)
function S.read(c)
    S.set_counts(c)
    S.poll()
    local out = { bank = st.bank, mode = st.mode, knob = st.knob, pad = st.pad, layout = st.layout,
                  mod_back = st.mod and 1 or 0, synced = st.synced }
    for _, id in ipairs((c and c.modifiers) or {}) do out["mod_" .. id] = st.mod and 1 or 0 end
    return out
end

-- let the editor assume a state (e.g. after Apply, ReaLearn parameters restart at 0)
function S.reset()
    st.bank, st.mode, st.knob, st.pad, st.layout, st.mod, st.synced = 0, 0, 0, 0, 0, false, false
end

function S.available() return true end

return S

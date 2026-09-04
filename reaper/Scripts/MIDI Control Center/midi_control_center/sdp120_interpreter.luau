-- ===== SDP-120 interpreter (fixed part; MODEL above is generated) =====================================
-- Builds the ReaLearn unit that sits on the Strich SDP-120's device input ("General MIDI"):
--   * swallows what the piano sends besides keys and pedals (Dummy targets; matched events never reach tracks),
--   * turns the tone-number entry into an echo the watcher can act on (program change on channel 1 -> CC on a
--     private channel, injected into the piano's own input, so instruments never see the patch changes),
--   * fires REAPER actions for the panel triggers (split voice, dual voice). The SUSTAIN button is left alone on
--     purpose: it also latches the piano's own sustain, which nothing on the REAPER side can undo.
-- Measured 2026-09-04, see docs/SDP120.md.

local M = MODEL
local F = M.filter or {}
local mappings = {}
local seen = {}
local function add(m)
    if seen[m.id] then return end
    seen[m.id] = true
    mappings[#mappings + 1] = m
end
local function swallow(id, name, source)
    add({ id = id, name = name, feedback_enabled = false, source = source, target = { kind = "Dummy" } })
end
local function action(cmd) return { kind = "ReaperAction", command = cmd, invocation = "Trigger" } end

-- channels the piano uses for accompaniment / demo playback (0-based); 1, 6 and 16 carry keys, dual and split
local PART_CHANNELS = { 1, 2, 3, 4, 6, 7, 8, 10, 11, 12, 13, 14 }

if F.keepalive then
    swallow("keepalive", "Keep-alive sysex (F0 33 00 F7)", { kind = "MidiRaw", pattern = "F0 33 00 F7" })
end
if F.gs_sysex then
    swallow("gs-sysex", "Roland GS sysex (reverb / chorus)", { kind = "MidiRaw", pattern = "F0 41 00 42 12" })
end
if F.metronome or F.rhythm then
    for n = 0, 127 do
        local is_click = (n == 75 or n == 76)
        if (is_click and F.metronome) or (not is_click and F.rhythm) then
            swallow("ch10-note-" .. n, "Channel 10 note " .. n, { kind = "MidiNoteVelocity", channel = 9, key_number = n })
        end
    end
end
if F.rhythm then
    for _, ch in ipairs(PART_CHANNELS) do
        swallow("part-pc-" .. ch, "Part program change ch " .. (ch + 1), { kind = "MidiProgramChangeNumber", channel = ch })
        for n = 0, 127 do
            swallow(string.format("part-note-%d-%d", ch, n), string.format("Part note ch %d", ch + 1),
                    { kind = "MidiNoteVelocity", channel = ch, key_number = n })
        end
    end
end
if F.panel_noise then
    -- what the panel sprays on the part channels: sustain/soft/sostenuto resets, bank, data entry, RPN, pan, reverb, chorus
    for _, ch in ipairs(PART_CHANNELS) do
        for _, cc in ipairs({ 0, 6, 10, 64, 66, 67, 91, 93, 100, 101 }) do
            swallow(string.format("noise-%d-%d", ch, cc), string.format("Panel CC %d ch %d", cc, ch + 1),
                    { kind = "MidiControlChangeValue", channel = ch, controller_number = cc, character = "Range" })
        end
    end
    swallow("noise-9-10", "Metronome pan (CC 10 ch 10)", { kind = "MidiControlChangeValue", channel = 9, controller_number = 10, character = "Range" })
end
if F.tone_changes then
    -- tone number entry: bank select 0 + program change on channels 1 and 2 (+ CC 64 = 0 on channel 1)
    swallow("tone-bank-ch1", "Tone bank select ch 1", { kind = "MidiControlChangeValue", channel = 0, controller_number = 0, character = "Range" })
    swallow("tone-bank-ch2", "Tone bank select ch 2", { kind = "MidiControlChangeValue", channel = 1, controller_number = 0, character = "Range" })
    swallow("part-pc-1", "Tone program change ch 2", { kind = "MidiProgramChangeNumber", channel = 1 })
    if M.echo_numbers then
        -- the number the player typed (display 001..128 = program 0..127) becomes CC echo_cc on the echo channel
        add({
            id = "tone-number-echo", name = "Tone number -> watcher echo", feedback_enabled = false,
            source = { kind = "MidiProgramChangeNumber", channel = 0 },
            target = {
                kind = "SendMidi",
                message = string.format("%02X %02X [0gfe dcba]", 0xB0 + M.echo_channel, M.echo_cc),
                destination = { kind = "InputDevice", device_id = M.input_device },
            },
        })
    else
        swallow("tone-pc-ch1", "Tone program change ch 1", { kind = "MidiProgramChangeNumber", channel = 0 })
    end
end

local T = M.triggers or {}
local function is_action(t) return type(t) == "table" and t.kind == "action" and t.command ~= nil end
if is_action(T.split_voice) then
    add({ id = "trigger-split-voice", name = "Split voice change (PC ch 16)", feedback_enabled = false,
          source = { kind = "MidiProgramChangeNumber", channel = 15 },
          glue = { target_interval = { 1, 1 } }, target = action(T.split_voice.command) })
end
if is_action(T.dual_voice) then
    add({ id = "trigger-dual-voice", name = "Dual voice change (PC ch 6)", feedback_enabled = false,
          source = { kind = "MidiProgramChangeNumber", channel = 5 },
          glue = { target_interval = { 1, 1 } }, target = action(T.dual_voice.command) })
end
if F.pedal_dupes then
    for _, ch in ipairs({ 5, 15 }) do
        for _, cc in ipairs({ 64, 66, 67 }) do
            swallow(string.format("pedal-dupe-%d-%d", ch, cc), "Pedal CC duplicate",
                    { kind = "MidiControlChangeValue", channel = ch, controller_number = cc, character = "Range" })
        end
    end
end

return { mappings = mappings }

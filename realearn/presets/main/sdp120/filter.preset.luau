--- name: Strich SDP-120 - input filter
--- realearn_version: 2.18.0
--- author: MIDI Control Center
--- description: |
---     The Strich SDP-120 digital piano (REAPER shows it as the generic "General MIDI" device) sends more than notes
---     and pedals. Measured 2026-09-04: a keep-alive sysex F0 33 00 F7 once a second forever; its metronome as notes
---     75/76 on channel 10; its rhythm accompaniment as drums on channel 10 plus parts on channels 11-15 with program
---     changes; a Roland GS sysex (F0 41 00 42 12 ...) and CC 91 / CC 93 on many channels when reverb or chorus is
---     changed; tone changes as bank select + program change on channel 16; and bursts of CC 64 = 0 on channels
---     2-15 after most panel actions.
---     This unit listens on the piano's device and "matches" the messages you do not want into a Dummy target;
---     ReaLearn does not pass matched events on to tracks, so they vanish before any track set to "all MIDI inputs"
---     sees them. Notes, pedals and everything not listed below pass through. Edit the SWALLOW flags to taste.
---     Unit input = the piano's device, no output.

--!strict

local SWALLOW = {
    keepalive   = true,    -- F0 33 00 F7 (the wireless-app ping, every second)
    metronome   = true,    -- notes 75 / 76 on channel 10 (the piano's click)
    rhythm      = true,    -- every other note on channel 10 plus channels 11-15 (built-in accompaniment)
    gs_sysex    = true,    -- Roland GS parameter sysex sent on reverb / chorus changes
    pedal_dupes = false,   -- the pedal CCs (64 / 66 / 67) are repeated on channels 6 and 16; keep them by default
}

local mappings = {}
local function swallow(id, name, source)
    table.insert(mappings, { id = id, name = name, feedback_enabled = false, source = source, target = { kind = "Dummy" } })
end

if SWALLOW.keepalive then
    swallow("keepalive", "Keep-alive sysex", { kind = "MidiRaw", pattern = "F0 33 00 F7" })
end
if SWALLOW.gs_sysex then
    -- GS DT1 messages: F0 41 <dev> 42 12 <addr x3> <data...> <sum> F7; match the fixed head (the rest varies)
    swallow("gs-sysex", "Roland GS sysex", { kind = "MidiRaw", pattern = "F0 41 00 42 12" })
end
if SWALLOW.metronome or SWALLOW.rhythm then
    for n = 0, 127 do
        local is_click = (n == 75 or n == 76)
        if (is_click and SWALLOW.metronome) or (not is_click and SWALLOW.rhythm) then
            swallow("ch10-note-" .. n, "Channel 10 note " .. n, { kind = "MidiNoteVelocity", channel = 9, key_number = n })
        end
    end
end
if SWALLOW.rhythm then
    for ch = 10, 14 do              -- 0-based channels 11-15: accompaniment parts (program changes + notes)
        swallow("part-pc-" .. ch, "Rhythm part program change ch " .. (ch + 1), { kind = "MidiProgramChangeNumber", channel = ch })
        for n = 0, 127 do
            swallow(string.format("part-note-%d-%d", ch, n), string.format("Rhythm part note ch %d", ch + 1),
                    { kind = "MidiNoteVelocity", channel = ch, key_number = n })
        end
    end
end
if SWALLOW.pedal_dupes then
    for _, ch in ipairs({ 5, 15 }) do
        for _, cc in ipairs({ 64, 66, 67 }) do
            swallow(string.format("pedal-dupe-%d-%d", ch, cc), "Pedal CC duplicate", { kind = "MidiControlChangeValue", channel = ch, controller_number = cc, character = "Range" })
        end
    end
end

return { mappings = mappings }

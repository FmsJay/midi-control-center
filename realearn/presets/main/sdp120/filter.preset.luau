--- name: Strich SDP-120 - sysex filter
--- realearn_version: 2.18.0
--- author: MIDI Control Center
--- description: |
---     The Strich SDP-120 digital piano (shown in REAPER as the generic "General MIDI" device) sends the sysex
---     F0 33 00 F7 about once a second, forever. Every track set to "all MIDI inputs" receives it and it fills
---     REAPER's recent-input list. This unit listens on that device and "matches" those messages into a Dummy target;
---     ReaLearn does not pass matched events on to tracks, so the sysex disappears while notes, pedal and every
---     other message from the piano pass through untouched. Unit input = the piano's device, no output.

--!strict

local mappings = {
    {
        id = "sdp120-keepalive",
        name = "Swallow the SDP-120 keep-alive sysex (F0 33 00 F7)",
        feedback_enabled = false,
        source = { kind = "MidiRaw", pattern = "F0 33 00 F7" },
        target = { kind = "Dummy" },
    },
}

return { mappings = mappings }

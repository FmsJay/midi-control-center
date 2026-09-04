# Oxygen Pro 61: what the keyboard actually sends and accepts

Everything here was measured on an Oxygen Pro 61 with firmware 2.1.2 on Windows 11 (2026-09-03) using
`tools/midi_capture.py` on ports 1 and 3 at the same time. Channels are written 1-based as on a MIDI monitor;
ReaLearn's Luau API uses 0-based channels, so subtract one there.

## USB ports

| # | Windows name | Carries |
|---|---|---|
| 1 | `Oxygen Pro 61` | keys, channel aftertouch (D0), pitch/mod wheels, MIDI clock in, Preset-mode pads (ch 10), Note-Repeat rolls (ch 1), Shift+Stop panic |
| 2 | `MIDIIN2/MIDIOUT2 (Oxygen Pro 61)` | 5-pin DIN pass-through |
| 3 | `MIDIIN3/MIDIOUT3 (Oxygen Pro 61)` | every DAW/Live-mode control; LED and pad writes go **in** here |
| 4 | `MIDIIN4/MIDIOUT4 (Oxygen Pro 61)` | Preset Editor |

## M-Audio private sysex (send to MIDIOUT3)

Header `F0 00 01 05 7F 00 00`, then `cmd 00 01 value F7`.

| cmd | value | Effect |
|---|---|---|
| `6D` | `02` | firmware mode = **Live** (Ableton). `00` = normal (DAW/Preset) |
| `6B` | `01` | LED control enable |
| `6C` | `03` | LED mode = software (host writes LEDs). `00` = firmware |
| `6E` | 0-7 | "control mode" in Ableton's script; no visible effect here |

Send `6D` first, then `6B`, then `6C` (the watcher waits 200 ms and 100 ms between them). All three are forgotten on
power-off. Live mode survives pressing Preset and DAW on the keyboard (they switch mode without a new sysex).

## Live-mode message map (port 3 unless noted)

| Control | Message |
|---|---|
| Mode button Off / Rec / Select / Mute / Solo | CC 57 / 58 / 59 / 60 / 61 **ch 16**, value 127 |
| Fader buttons 1-8 | CC 32-39 ch 1, **latching**: alternate presses send 127 and 0 |
| Bank < / > | CC 110 / 111 ch 1, press only. The keyboard stops paging its own banks |
| Faders 1-8, master | CC 12-19, CC 41 ch 1 (7-bit) |
| Knobs 1-8 | CC 22-29 ch 1, absolute |
| Shift | CC 105 **ch 13**, 127 held / 0 released |
| Shift + pad 9 / 10 / 11 | CC 85 / 86 / 87 ch 16 (knob function Pan / Device / Sends). CC 83 = Volume in Ableton's map; no button was found that sends it |
| Pads 1-16 | notes ch 1 with velocity, Ableton layout: top row 40 41 42 43 48 49 50 51, bottom row 36 37 38 39 44 45 46 47 |
| Pad side buttons top / bottom | CC 107 / 108 ch 1, momentary |
| Loop / << / >> / Stop / Play / Rec | CC 114 / 115 / 116 / 117 / 118 / 119 ch 1 (Play and Stop also emit MIDI Start/Stop on port 1) |
| Encoder turn | CC 103 ch 1 relative: 65 = +1, 63 = -1 (ReaLearn character `Relative2`) |
| Encoder press | CC 102 ch 1 |
| Back | CC 104 ch 1, 127 held / 0 released |
| Preset / DAW | CC 112 / 113 ch 1 |
| Tempo, Note Repeat | nothing on any port (keyboard-local) |
| Shift + Stop | CC 121 (reset controllers) + CC 123 (all notes off) on all 16 channels of **port 1** |
| Keys | notes + channel aftertouch on port 1 |

### Firmware behaviour that limits a host

- **No two-button chords.** While any button is held the keyboard sends nothing for a second button (measured for
  Back + << / Bank / Play and Shift + Play / Record / Loop / pad / fader button). Shift + pads 9-11 and 13-16 are
  firmware-synthesised exceptions. A host modifier therefore has to be a latch, not a hold.
- **Shift + fader button** opens the keyboard's own edit menu and the Shift *release* is not sent; CC 104 value 0
  arrives instead.
- **Shift + << / >>** type zoom keystrokes (no MIDI). **Shift + pads 13-16** type Save / Quantize / View / Undo
  keystrokes. **Shift + Tempo** sends nothing at all in Live mode, not even a keystroke.
- **Shift + knobs 1-4** edit the arpeggiator locally (Type / Octave / Gate / Swing); knobs 5-8 send their normal CCs.
- **Note Repeat** while active reroutes pad rolls to port 1 channel 1, bypassing whatever the pads are mapped to.
- **No MIDI clock out** in Internal tempo mode. Keep Clock = External so the arpeggiator and Note Repeat follow
  REAPER's clock on port 1 (they pause while REAPER is stopped).
- **The OLED is not host-writable** in Live mode (control-mode sysex and echoed control messages change nothing).
- **The fader buttons keep their local functions in Live mode** when no Mode is selected: ARP, Latch, Chord, Scale, time
  divisions. The firmware gives no sign of it on its own LEDs, and an arpeggiator left on with Clock = External silences
  the keys whenever REAPER is stopped. The generated preset mirrors those four toggles on LEDs 1-4 in Off mode.
- **ReaLearn auto units expose no readable parameters**: the Helgobox instance's FX parameters belong to its own main
  unit ("Main p1"...), not to units created from controllers.json. To follow a unit's state from a script, have the
  preset echo state-changing presses into the port-1 input (`SendMidi` -> `InputDevice`) and read them back with
  `MIDI_GetRecentInputEvent`. A `vst_chunk` get/set round trip on the Helgobox instance makes it re-read a changed
  preset file without restarting REAPER (verified).

## LED feedback (write to MIDIOUT3, after the unlock)

| Target | Message |
|---|---|
| Fader button n (1-8) LED | CC 31+n ch 1, value 127 on / 0 off (the Ableton echo format). Mackie notes and HUI zone writes do nothing |
| Pad colour | note-on ch 1, key = pad note from the layout above, velocity = colour code |
| Mode LEDs, transport LEDs, OLED | not writable |

Pad colour codes (fixed 13-colour table; any other value shows as off):

| code | colour | code | colour |
|---|---|---|---|
| 0 | off | 44 | aqua |
| 3 | red | 48 | blue |
| 11 | orange | 50 | violet |
| 12 | green | 51 | magenta |
| 14 | chartreuse | 56 | azure |
| 15 | yellow | 60 | cyan |
| 35 | rose | 63 | white |

Add 64 to a code to make the pad blink. Writes must be on channel 1 even though Preset-mode pads transmit on channel 10.

## Preset (non-Live) mode, for reference

With `6D` = 0 the keyboard behaves as the manual describes: firmware presets or the User DAW preset decide what each
control sends, banks page inside the keyboard, pads transmit on port 1 channel 10, and only the pads and fader
buttons remain paintable after the LED unlock. The abandoned DAW-mode design and its preset builder are kept under
`docs/legacy-*.md` and `tools/legacy/` for anyone who needs the `.OxygenPro61DawPreset` byte layout.

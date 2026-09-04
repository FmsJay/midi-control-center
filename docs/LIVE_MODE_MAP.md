# Oxygen Pro 61 in Live mode — the host-defined layout (current design, 2026-09-03)

The keyboard runs in its Ableton "Live" firmware mode (sysex `F0 00 01 05 7F 00 00 6D 00 01 02 F7`), put there by
`REAPER/Scripts/MIDI Control Center/Oxygen Pro - Live watcher.lua` (started from `__startup.lua`) at every REAPER start and
after every keyboard power-on, together with the LED unlock. In that mode everything reports on USB port 3, the
keyboard does no bank paging of its own, and ReaLearn holds all state. One ReaLearn unit:
`Data/helgoboss/realearn/presets/main/oxygen-pro-61/live.preset.luau`, input `MIDIIN3` (control-only in REAPER),
output `MIDIOUT3`. Interactive version of this page: `oxygen_live_map.html`.

Measured message map: `PROTOCOL.md`. Everything here is the shipped default; the editor (`MIDI Control Center.lua`) can change all of it.

## Global (every bank, every layout)

| Control | Function |
|---|---|
| Mode button | what the fader buttons and their LEDs mean: Off, Record, Select, Mute, Solo. In Off mode the buttons are the keyboard's own ARP / Latch / Chord / Scale / time-division keys and LEDs 1-4 show those four toggles |
| Shift + pad 9 / 10 / 11 | knob function: Pan / Device (focused FX params 1-8) / Send 1 of each track |
| (CC 83, if any button sends it) | knob function: sends 1-8 of the selected track |
| Bank < / Bank > | fader bank 1-4; the pad with the new bank number flashes white for half a second (ReaLearn echoes CC 110/111 to port 1, the watcher flashes). After Back: previous / next marker |
| Side buttons beside the pads (top / bottom) | previous / next pad mode, wrapping |
| **DAW button** | steps through the **layouts** (only the pad modes and Back combos differ; one layout ships, add more in the editor). The watcher answers each press with a one-second pad sweep in the layout's colour (green for General DAW). The keyboard's screen cannot be written to in Live mode and keeps saying Ableton |
| Master fader | master volume |
| Transport | play/stop, stop, record, repeat; << >> = go to start / end (actions 40042 / 40043). Shift + any of these is swallowed by the firmware (Shift + << / >> types zoom keystrokes; Shift + Play / Record / Loop send nothing). |
| Encoder | browse tracks (selection follows); after Back: zoom |
| Preset button | leaves Live mode for Preset mode: keys and pads play on port 1; DAW button returns |
| Note Repeat / Latch | local: while held or latched the pads roll and their notes leave on **port 1 channel 1** (not port 3), bypassing the pad modes; release restores them (measured) |
| Tempo | keyboard-internal only; the button sends nothing and the keyboard emits no MIDI clock in Internal mode (measured). Keep Clock = **External** so ARP/Note Repeat follow REAPER while it plays (they pause when REAPER is stopped). |
| Encoder press | **tap tempo** for REAPER: 2+ presses within 2 s set the project BPM (whole BPM, 30-300). ReaLearn echoes CC 102 into port 1; the Live watcher does the maths and calls `SetCurrentBPM`. |
| **Back = one-shot layer (press, then)** | Press Back: the pads switch to a violet/rose checkerboard and the Back layer is armed. The next press fires the alternate function and drops the layer (pads repaint): << / >> = undo / redo (40029 / 40030) · Bank < / > = previous / next marker (40172 / 40173) · Play = insert marker (40157) · Record = metronome on/off (40364) · Loop = toggle mixer (40078) · Stop = save project (40026) · encoder turn = zoom out / in (1011 / 1012, layer stays armed) · encoder press = insert new track (40001). Back again = cancel. Measured 2026-09-03: while any button is held the keyboard sends nothing for a second button, so neither Shift nor Back can be a hold-modifier. |
| Shift + Tempo | nothing in Live mode: no MIDI and no keystroke (measured 2026-09-03 with a system-wide key-down probe). Metronome = Back + Record or the Markers pad. |
| Shift + Stop | MIDI panic: CC 121 + CC 123 on all 16 channels of port 1 (measured) |
| Shift + pads 13-16, Shift + Tempo | computer keystrokes (Save/Quantize/View/Undo, metronome); no MIDI (measured) |
| Shift + fader button, Shift + Play / Record / Loop / pad | no MIDI reaches the host (measured 2026-09-03); Shift + fader button opens the keyboard's own edit menu and even the Shift release goes missing (CC 104 value 0 arrives instead). Shift + knobs 1-4 = arpeggiator settings (firmware); Shift + knobs 5-8 send their normal CCs |
| Keys | notes + channel aftertouch on port 1; Octave, Back: local |

## Fader banks

| Bank | Faders 1-8 | Knobs 1-8 | Fader buttons (per Mode) |
|---|---|---|---|
| 1 | tracks 1-8 volume | tracks 1-8 by knob function | tracks 1-8 arm / select / mute / solo, toggles |
| 2 | focused FX params 1-8 | focused FX params 9-16 | Select: FX slot 1-8 on/off on the selected track; Mute: 1 mute, 2 solo, 3 arm, 4 all-FX bypass (selected track) |
| 3 | tracks 9-16 volume | tracks 9-16 by knob function | tracks 9-16 arm / select / mute / solo |
| 4 | free | free | dark |

Fader buttons are latching in Live mode (127 / 0 on alternate presses); ReaLearn treats every message as a press,
so one press = one toggle. Select buttons toggle tracks in and out of the selection (additive).

## Pad modes (per layout; the editor can add drums / mixer / custom / free modes)

| # | General DAW layout |
|---|---|
| 1 | **Drums**: hits re-emitted into the `Oxygen Pro 61` port-1 input as channel-10 notes 36-51; blue at rest, green / yellow / red by hit |
| 2 | Mixer tracks 1-8: pads 1-8 mute (red / chartreuse), 9-16 solo (yellow / azure) |
| 3 | Mixer tracks 9-16, same colours |
| 4 | Markers & utilities: 1-8 go to marker 1-8 (orange); 9 insert marker (white); 10/11 previous/next marker (azure); 12 repeat (yellow when on); 13/14 undo/redo (violet); 15 save (green); 16 metronome (magenta when on) |
| 5 | Free (white) |

All LEDs and pad colours are feedback from REAPER's actual state and repaint on Mode, bank, pad-mode or layout
changes, and on any change made with the mouse, an action or automation.

## Files

| File | Role |
|---|---|
| `REAPER/Scripts/MIDI Control Center/Oxygen Pro - Live watcher.lua` | keeps the keyboard in Live mode; auto-started |
| `REAPER/Scripts/MIDI Control Center/MIDI Control Center - Setup.lua` | new machine: device numbers, controllers.json, preset constant, monitoring FX, prefs checklist |
| `REAPER/Scripts/MIDI Control Center/Oxygen Pro - LED unlock.lua`, `oxygen_led_unlock.py [--restore]` | manual re-arm / return to factory presets (Python optional) |
| `REAPER/Helgoboss/ReaLearn/controllers.json` | managed controllers -> auto units |
| `backup-2026-09-03-livemode/`, `backup-2026-09-03-dawmode/` | snapshots |

## Things to know

- Faders are 7-bit CC in this mode (128 steps) instead of Mackie 14-bit.
- Pads are control surfaces here; drum mode re-injects them so drum tracks keep their normal port-1 input.
- Marker/utility action IDs in the General layout are REAPER defaults and should be confirmed once in the Actions window.
- Whether Live mode survives a keyboard power-off is untested; the watcher re-sends it regardless.

# Oxygen Pro 61 — User DAW preset "REALRN" and ReaLearn layout

Design of 2026-09-03. Everything here follows from measured facts recorded in the
`reaper` skill's FINDINGS.md (F-0011 … F-0017):

- DAW-mode faders, knobs, fader buttons, transport, bank and encoder messages leave on
  USB **port 3** (`MIDIIN3 (Oxygen Pro 61)`); pads leave on **port 1** (`Oxygen Pro 61`).
- Fader-button LEDs light only from **CC 32–39 on channel 1 sent to port 3**, value 127 = on,
  0 = off, and only after the M-Audio unlock sysex (`oxygen_led_unlock.py`).
- Pad LEDs light only from **note-on on channel 1 sent to port 3**, note = pad number in the
  Ableton layout below, velocity = colour code. Fixed palette: 0 off, 3 red, 11 orange,
  12 green, 14 chartreuse, 15 yellow, 35 rose, 44 aquamarine, 48 blue, 50 violet,
  51 magenta, 56 azure, 60 cyan, 63 white; +64 = blink.
- The keyboard sends nothing when the Mode button (Rec/Select/Mute/Solo) changes, and
  forgets the LED unlock on every power-off.

Pad LED address (note number) = pad position, independent of what the pad transmits:

```
top row    pads 1-8  : 40 41 42 43 48 49 50 51
bottom row pads 9-16 : 36 37 38 39 44 45 46 47
```

## Channel plan

| Bank | Channel | Role |
|---|---|---|
| 1 | 1 (Mackie where noted) | Mixer, tracks 1–8 + master |
| 2 | 2 | Selected track and focused FX |
| 3 | 3 | Mixer, tracks 9–16 |
| 4 | 4 | Free — nothing in ReaLearn, for REAPER MIDI-learn |

Pads keep channel 10 in bank 1 (they play instruments) and use channels 2/3/4 in banks 2–4.

## Per-control assignments

### Faders (9)
| Bank | Message |
|---|---|
| 1 | Mackie (pitch bend ch 1–9; fader 9 = master) |
| 2 | CC 20–28 ch 2 — faders 1–8: focused FX params 1–8, fader 9: selected track volume |
| 3 | CC 20–28 ch 3 — tracks 9–16 volume, fader 9: master |
| 4 | CC 20–28 ch 4 — free |

### Knobs (8)
| Bank | Message |
|---|---|
| 1 | Mackie (V-pot CC 16–23, relative type 3) — track pan 1–8 |
| 2 | CC 102–109 ch 2 — focused FX params 9–16 |
| 3 | CC 102–109 ch 3 — tracks 9–16 pan |
| 4 | CC 102–109 ch 4 — free |

### Fader buttons (8, four Mode assignments each)
CC, press 127 / release 0, channel = bank channel (bank 1 = ch 1).

| Mode | CC | Bank 1 target | Bank 2 target | Bank 3 target |
|---|---|---|---|---|
| Select | 32–39 | toggle track 1–8 in/out of the selection (additive, like Ctrl-click) | FX slot 1–8 on/off (selected track) | toggle track 9–16 |
| Mute | 40–47 | mute 1–8 | 40 mute, 41 solo, 42 arm, 43 all-FX bypass (selected track) | mute 9–16 |
| Solo | 48–55 | solo 1–8 | — | solo 9–16 |
| Record | 56–63 | arm 1–8 | — | arm 9–16 |

LEDs: the eight lights always show the state of **the mode you last pressed a button in**
(ReaLearn learns the mode from the CC range of the last press, since the keyboard does not
announce Mode changes). Feedback is bank-gated by the bank parameter.

### Pads (16)
| Bank | Message | Meaning | LED |
|---|---|---|---|
| 1 | Note 36–51 ch 10 (as factory) | play instruments | colour ramp by velocity: green → yellow → red, blue at rest |
| 2 | CC 36–51 ch 2 | pads 1–8 `_LOOPCANVAS_PRESS_SLOT_1..8`, pads 9–16 `_LOOPCANVAS_DROP_SLOT_1..8` | green / azure |
| 3 | CC 36–51 ch 3 | pads 1–8 `_LOOPCANVAS_RETURN_SECTION_1..8`, pads 9–16 `_LOOPCANVAS_ALIGN_SLOT_1..8` | yellow / violet |
| 4 | CC 36–51 ch 4 | free | white |

### Transport, bank, encoder
| Control | Message | ReaLearn |
|---|---|---|
| << >> Stop Play Rec Loop | Mackie notes 91 92 93 94 95 86 (ch 1) | transport |
| Bank < / Bank > | CC 14 / CC 15 ch 1, press 127 | bank parameter −1 / +1 (0–3) |
| Encoder turn | Mackie (CC 60 relative) | browse tracks (selection follows) |
| Encoder press, Back | as factory | unused |

## ReaLearn instances (monitoring FX chain)
| Instance | Input | Output | Preset |
|---|---|---|---|
| Oxygen Surface | `MIDIIN3 (Oxygen Pro 61)` | `MIDIOUT3 (Oxygen Pro 61)` | `oxygen-pro-61/surface` |
| Oxygen Pads | `Oxygen Pro 61` (port 1) | `MIDIOUT3 (Oxygen Pro 61)` | `oxygen-pro-61/pads` |

Both are needed because pads arrive on a different USB port than everything else, and a
ReaLearn instance reads one input device. The pads instance infers the bank from the pad
channel (10/2/3/4), so its colours repaint on the first pad hit after a bank change.

## Every power-on
The keyboard reverts to firmware LEDs when powered off. `oxygen_led_watch.py` re-sends the
unlock whenever port 3 reappears and then fires REAPER action
"Helgobox/ReaLearn: Send feedback for all instances" through the web interface so all
lights repaint from REAPER's actual state.

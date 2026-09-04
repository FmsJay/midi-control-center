# Exquis (Intuitive Instruments) as a second surface

Research date 2026-09-04, Exquis app 3.0.0, Developer Mode spec 2025-03-10. The keyboard needs **firmware 2.1 or
newer** for Developer Mode (hold Settings, then press Settings again: green hexagons show major.minor.patch).

## What the device is, in MIDI terms

- One USB-MIDI port pair named **Exquis** (Windows and macOS), carrying notes and control together. TRS MIDI in/out
  and CV outputs exist too; the host API answers only on USB.
- 61 hexagonal keys with velocity (strike and lift), X tilt = pitch bend, Y tilt = CC 74, pressure = channel
  pressure (MPE) or poly aftertouch. Default is **MPE**: channel 1 master, member channels 2-15, **channel 16 is
  reserved for host communication**. 4 clickable encoders with RGB LEDs, 10 backlit buttons (Settings, Sound,
  Record, Loop, Clips, Play/Stop, Down, Up, Undo, Redo), a 6-zone capacitive slider, RGB under every key.
- Standalone (no Developer Mode) the encoders send CC 41-44 (clicks CC 21-23, click 4 = MPE freeze), three of the
  buttons send CC 32 (toggle) / 33 / 34 (momentary); all configurable in the app.

## Developer Mode (what the host can do)

Sysex frame `F0 00 21 7E 7F <cmd> ... F7`.

| cmd | meaning |
|---|---|
| `00 <mask>` | enter Developer Mode for the zones in the bit mask; `00 00` leaves it. Bits: 01 pads, 02 encoders, 04 slider, 08 Up/Down, 10 Settings/Sound, 20 the other buttons |
| `02` | read / write the 128-entry colour palette |
| `03 [page]` | refresh notice, sent by the device when it enters (7F) or leaves its settings menu (LEDs reset) |
| `04 <id> r g b fx [r g b fx ...]` | set LED colours of consecutive elements, RGB 0-127 each, `fx` 00 none / 3F pulse to black / 7F pulse to white / 3E pulse red / 7E pulse green / 00-3D alpha / 40-7D blend to white |
| `05 msb lsb`, `06 note`, `07 scale`, `08 d0..d11`, `09 <255 bytes>` | tempo, root note, scale number, custom scale, full snapshot; the device also sends 05/06/07 when they change |

Taken-over zones report on **channel 16**: pads `9F <pad> 7F` / `8F <pad> 00` (fixed velocity, no expression),
buttons and encoder pushes `BF <id> 7F|00`, encoders `BF <id> <64±n>` (relative, ReaLearn character
`Relative2`), slider `BF 5A <zone 0-5>` (127 on release). Element ids: pads 0-60 (bottom-left to top-right),
slider zone LEDs 80-85, slider position 90, buttons 100 Settings, 101 Sound, 102 Record, 103 Loop, 104 Clips,
105 Play/Stop, 106 Down, 107 Up, 108 Undo, 109 Redo, encoders 110-113, encoder pushes 114-117.

The one hard limit: **taken-over pads lose MPE** (they become fixed-velocity buttons). So this integration takes
over everything except the pads (mask `2E`), and the pads keep sending MPE on channels 2-15 straight to your
instrument tracks. ReaLearn only matches channel-16 messages and sysex; unmatched notes pass through.

Independent of Developer Mode, Note On/Off received on **channel 1** lights the matching pad green ("MIDI
Score") - a cheap way to show something on the keys from REAPER.

## The Exquis app

The app (3.0.0 on this drive) is a JUCE plug-in host and looper with the layout / scale / CC / curve editor
inside. It opens the Exquis port itself and repaints the LEDs, the vendor says it is "not designed to be used in
conjunction with other applications", and with the app connected the buttons and encoders stop sending CCs. Use
it to program layouts and curves, then **close it**; REAPER owns the port. No loopback or virtual port is
needed. Running both at once would need a virtual port in between and would still fight over the LEDs, so it
is not supported here.

## This integration

`realearn/presets/main/exquis/main.preset.luau`, a ReaLearn unit with input and output = Exquis (enable the
device as input, control and output in REAPER). On load it sends the mask-2E Developer Mode command and paints
the LEDs; when the unit unloads it hands the zones back (`00 00`). If the buttons ever stay dead (REAPER closed
hard), run the action `Exquis - Developer mode off` or power-cycle the Exquis.

| Control | Normal | Holding the FCB1010 shift switch |
|---|---|---|
| Play/Stop | play / stop, green when playing | insert marker |
| Record | record, red when armed | metronome on/off |
| Loop | repeat, yellow when on | show / hide mixer |
| Clips | insert marker (white) | save project |
| Undo / Redo | undo / redo (violet) | previous / next marker |
| Down / Up | previous / next track (azure) | zoom out / in |
| Encoder 1 | selected track volume (green) | master volume (red) |
| Encoder 2 | selected track pan (azure) | selected track send 1 (yellow) |
| Encoder 3 | browse tracks (white) | zoom out / in (cyan) |
| Encoder 4 | project tempo (orange) | - |
| Encoder pushes 1-3 | mute / solo / arm the selected track, LED shows the state | same |
| Encoder push 4 | tap tempo (through the Oxygen watcher) | same |
| Slider zones 1-6 | go to marker 1-6 (orange) | same |

The shift comes from the FCB1010 bridge unit, which injects CC 105 on channel 14 into the Exquis input as well as
into the Oxygen's port (see `FCB1010_SHIFT.md`). Edit the preset to change the layout; it is a short Luau file
with helpers `button`, `shifted`, `led`, `paint`.

## Sources

Developer Mode specification (Intuitive Instruments, via dualo.com resources), Exquis User Guide 3.0.0, the
vendor FAQ and forum, and the LGPL-3.0 DrivenByMoss sources (`controller/intuitiveinstruments/exquis`), which
implement the same protocol for Bitwig and REAPER. The Ableton remote script's licence was not checked.

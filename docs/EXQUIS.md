# Exquis (Intuitive Instruments) as a second surface

Research date 2026-09-04, Exquis app 3.0.0, Developer Mode spec 2025-03-10; verified on hardware with firmware 3.0.0 the
same day (transport, LEDs, encoders, pushes, slider, keys passing through). The keyboard needs **firmware 2.1 or newer**
for Developer Mode. A quick way to read the firmware without the keyboard's menu: the USB descriptor revision
(`USB\VID_2985&PID_0007&REV_xxxx` in Device Manager) is the firmware version, `REV_0200` = 2.0.0.

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
| `05 msb lsb`, `06 note`, `07 scale`, `08 d0..d11`, `09 <255 bytes>` | tempo, root note, scale number, custom scale, full snapshot; the device also sends 05/06/07 when they change. **Snapshot layout (decoded 2026-09-04):** 11 header bytes (`00 01 30 0E 00 00 00 01 00 00 00` here), then 61 x 4 bytes = note number, red, green, blue (0-127) for every key, bottom-left key first, rows upward; the editor identifies the active layout file from those notes and draws the keys in those colours |

Taken-over zones report on **channel 16**: pads `9F <pad> 7F` / `8F <pad> 00` (fixed velocity, no expression),
buttons and encoder pushes `BF <id> 7F|00`, encoders `BF <id> <64±n>` (relative, ReaLearn character
`Relative2`, accelerated: fast turns send larger steps), slider zones `BF 50..55 7F|00` (measured on firmware 3.0.0: each
zone is its own button on CC 80-85; the spec's `BF 5A <zone>` form was not seen). Play/Stop also emits MIDI Start (`FA`). Element ids: pads 0-60 (bottom-left to top-right),
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

The Exquis has **modes**, like the keyboard's pad modes: each mode is a full set of button, encoder, push and slider
assignments plus its shift layer. A button or encoder push assigned "Next Exquis mode" steps through them on the
device (its LED shows the mode's colour), the editor follows along, and "Mode settings" in the editor names and colours
them. The **slider** stays the keyboard's own arpeggiator-rate slider by default (`slider_mode = "native"`); switch it
to "zones" to get six REAPER buttons per mode instead.

Two modes ship: **Track** (below) and **Device**, where the four encoders are the focused FX's parameters 1-4 (5-8 with
the foot switch) and everything else is as in Track. Clips is the mode-switch button in both.

`realearn/presets/main/exquis/main.preset.luau`, a ReaLearn unit with input and output = Exquis (enable the
device as input, control and output in REAPER). On load it sends the mask-2E Developer Mode command and paints
the LEDs; when the unit unloads it hands the zones back (`00 00`). If the buttons ever stay dead (REAPER closed
hard), run the action `Exquis - Developer mode off` or power-cycle the Exquis.

| Control | Normal | Holding the FCB1010 shift switch |
|---|---|---|
| Play/Stop | play / stop, green when playing | insert marker |
| Record | record, red when armed | metronome on/off |
| Loop | repeat, yellow when on | show / hide mixer |
| Undo / Redo | undo / redo (violet) | previous / next marker |
| Down / Up | previous / next track (azure) | zoom out / in |
| Encoder 1 | selected track volume (green) | master volume (red) |
| Encoder 2 | selected track pan (azure) | selected track send 1 (yellow) |
| Encoder 3 | browse tracks (white) | zoom out / in (cyan) |
| Encoder 4 | project tempo (orange) | - |
| Encoder pushes 1-3 | mute / solo / arm the selected track, LED shows the state | same |
| Encoder push 4 | tap tempo (through the Oxygen watcher) | same |
| Clips | next Exquis mode (LED = mode colour) | save project |
| Slider | native: arpeggiator rate (zones mode: go to marker 1-6, orange) | same |

The encoders and pushes act on the **selected** track, so the Exquis is the "what I am working on" surface while the
Oxygen keeps its fixed track banks. The shift comes from the FCB1010 bridge unit, which injects CC 105 on channel 14 into the Exquis input as well as
into the Oxygen's port (see `FCB1010_SHIFT.md`). Change the layout in the editor (Device switch > Exquis); the preset is generated from `model.exquis` by
`midi_control_center/exquis_interpreter.luau`, and `tests/test_exquis.py` keeps it equal to the golden reference.

## Layouts, the app, and keeping your layout across restarts

The note layout of the keys is not something REAPER sets; it lives on the Exquis. The Exquis app's Note Layout Editor
builds **isomorphic** layouts from two semitone intervals ("the number of semitones between two pairs of hexagons,
propagated to the entire keyboard") or **free** layouts with a MIDI value and colour per key, and can flip the
expression axes for a keyboard used sideways. The keyboard stores 8 layouts; pick one on the device by holding the second of the two top-left buttons
(the spec calls it Sound, the guide "Settings (2)") and turning encoder 3. Holding the first (Settings) gives the
keyboard page with tonic and scale. The vendor's own rule is "do not use the Exquis application simultaneously with another software or
synthesizer". On Windows 11 (multi-client MIDI) the app can be open next to REAPER **if REAPER was started first**:
notes still reach REAPER and the layout editor works live. But while the app is connected it takes the buttons for
itself (measured 2026-09-04: Play on the Exquis no longer reaches REAPER) and repaints the LEDs. Rule of thumb: open
the app only to edit layouts or settings, then close it; the ReaLearn unit gets its controls and colours back on the
next Apply or REAPER restart.

A Jankó-style layout is the isomorphic rule "2 semitones along one axis, 1 semitone along the other" (whole tones
along a row, the next row a semitone up, so every other row repeats). With the keyboard on its side (encoders on the
left, buttons and slider on the right) choose the axis that runs left-right for you as the 2-semitone one and flip
the X/Y expression axes in the editor so pitch bend still follows sideways finger movement.

**Shipped layouts** (`exquis-layouts/*.xqilayout`; the generated ones come from `tools/exquis_layouts.py`), for the
keyboard on its side:

0. *Janko (True Janko V1)*: a hand-made Jankó layout (free layout, chromatic along the file rows, whole tones on the
   diagonals) that is the layout actually in use here; copied from the app's Layouts folder.

1. *REAPER Piano (sideways)*: white keys run along the player's rows (5 per row, C3 upward, 3.5 octaves), black keys
   sit raised between them on the row above, with the piano's gaps at E-F and B-C left unlit and the boundary sharps
   duplicated at both row ends. Whites white, blacks dark violet.
2. *REAPER Drums 4x4*: sixteen pads, notes 36-51, four colour rows in the lower-left corner; everything else unlit.
3. *Exquis default*: the factory isomorphic rule (chromatic along a row, +3 up-left, +4 up-right), C3 bottom-left,
   C keys blue.

The `.xqilayout` format is plain XML: a `<LAYOUT>` header (`isomorphic`, `topLeftInterval`, `topRightInterval`,
`transpose`, `flipX/flipY/flipXY`) and 61 `<NOTE noteNumber colour>` entries listed from the bottom-left key, row by
row upward (rows alternate 6 and 5 keys). Load them in the app's Standalone Settings window, drag them into layout
slots, close the window (that writes them to the keyboard).

To make REAPER put the keyboard into your chosen layout every time it starts: set the layout on the device, then run
the action **Exquis - Capture layout snapshot** once. It stores the Developer-Mode snapshot (layout + MIDI settings)
in `midi_control_center/exquis_snapshot.txt`; from the next Apply on, the Exquis unit restores it on load. Delete the file to
stop that. Leaving the keyboard's own Settings menu resets its LEDs; the Live watcher notices the refresh message and
repaints them.

## Sources

Developer Mode specification (Intuitive Instruments, via dualo.com resources), Exquis User Guide 3.0.0, the
vendor FAQ and forum, and the LGPL-3.0 DrivenByMoss sources (`controller/intuitiveinstruments/exquis`), which
implement the same protocol for Bitwig and REAPER. The Ableton remote script's licence was not checked.

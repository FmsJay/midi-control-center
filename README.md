# Oxygen Pro 61 Rich REAPER Integration

Two-way integration of the **M-Audio Oxygen Pro 61** with **REAPER**, built on **ReaLearn** (Helgobox).
The keyboard runs in its Ableton "Live" firmware mode, which the host can unlock over sysex. In that mode every
control reports on one USB port, the fader-button LEDs and the sixteen RGB pads become writable, and REAPER's real
state drives them: what lights up is what REAPER says is true, never an echo of what you pressed.

Interactive map of every control: open `docs/oxygen_live_map.html` in a browser. Text version: `docs/LIVE_MODE_MAP.md`.

## What you get

- **Fader buttons follow the Mode button**: Off, Record-arm, Select, Mute, Solo. One press toggles, LEDs show the true
  state of tracks 1-8 (bank 1), FX slots (bank 2) or tracks 9-16 (bank 3), and repaint on any change made with the
  mouse, an action or automation.
- **Four virtual fader banks** on the keyboard's Bank buttons (the firmware does no paging in Live mode; ReaLearn does).
  The pad with the new bank number flashes white when you switch.
- **Faders** = track volume (banks 1 and 3), focused-FX parameters (bank 2). **Master fader** = master volume.
- **Knobs** switch function with Shift + pad 9 / 10 / 11: pan, focused-FX parameters, send 1; a fourth mode drives
  the selected track's sends 1-8.
- **Pad modes** stepped with the two side buttons, colours change instantly: drums (hits re-injected into the
  port-1 input on channel 10, colour by velocity), mixer mute/solo pads with live state colours, markers and utilities,
  and a second layout reserved for a looper (work in progress, see below).
- **Two layouts** toggled by the DAW button (General DAW, and the work-in-progress LoopCanvas layout), with a green
  or azure pad sweep as the indicator, because the keyboard's screen cannot be written from the host.
- **Transport**, go to start / end, **encoder** browses tracks, **encoder press = tap tempo** (sets REAPER's BPM).
- **Back = one-shot layer**: press Back (pads show a violet/rose checkerboard), then a button: << / >> undo / redo,
  Bank < / > previous / next marker, Play insert marker, Record metronome, Loop mixer, Stop save, encoder zoom /
  insert track.
- **Aftertouch, chord mode, scale mode, arpeggiator, note repeat** keep working; they are keyboard-local.
- **Self-healing**: a ReaScript watcher re-arms Live mode and the LEDs every time the keyboard is powered on.

## Requirements

| Piece | Tested with | Notes |
|---|---|---|
| REAPER | 7.79, Windows 11 | Any 7.x should work. macOS/Linux untested (port names differ, see below) |
| Helgobox (ReaLearn) | 2.18.2 | <https://www.helgoboss.org/projects/helgobox/> - install the VST3 or VST2 into REAPER |
| Oxygen Pro 61 firmware | 2.1.2 | Older firmware may not have the Live mode. Update with M-Audio's installer |

That is all the core needs: no Python, no extra MIDI drivers, no other extensions. See *Optional extras* below for the diagnostic tools and the work-in-progress looper layout.

The keyboard shows up as four MIDI ports. This integration uses:

| Windows port name | Role |
|---|---|
| `Oxygen Pro 61` | port 1: keys, aftertouch, Preset-mode pads, MIDI clock in. REAPER: input + control |
| `MIDIIN3 (Oxygen Pro 61)` | port 3: every Live-mode control. REAPER: **control messages only** |
| `MIDIOUT3 (Oxygen Pro 61)` | port 3 out: sysex, LED and pad colour writes. REAPER: output enabled |

Leave `MIDIIN2/4` and `MIDIOUT2/4` disabled. On macOS the names are different (`Oxygen Pro 61 USB MIDI`,
`Oxygen Pro 61 Mackie/HUI`, `Oxygen Pro 61 Editor`); edit the names at the top of the watcher and the setup script.

## Install on a fresh REAPER

1. Install Helgobox and start REAPER once so it scans the plugin.
2. Plug the keyboard in over USB. Any firmware preset is fine; the watcher switches it to Live mode itself.
3. From this folder, in PowerShell:

       .\install.ps1 -ReaperResourcePath "D:\REAPER"       # the folder that contains reaper.ini

   Without the parameter it targets `%APPDATA%\REAPER`. The script copies the ReaLearn presets to
   `Data\helgoboss\realearn\presets\main\oxygen-pro-61\`, the ReaScripts to `Scripts\Oxygen Pro\`, and appends
   the watcher block to `Scripts\__startup.lua`. Without PowerShell, copy those files by hand; the layout of this
   repo mirrors the REAPER resource folder (`realearn/` maps to `Data/helgoboss/realearn/`).
4. Start REAPER. Actions > Show action list > New action > Load ReaScript >
   `Scripts\Oxygen Pro\Oxygen Pro - First time setup.lua`, then run it. It finds the keyboard's device numbers,
   writes `Helgoboss\ReaLearn\controllers.json`, patches the drum-injection device inside the preset, puts Helgobox
   in the monitoring FX chain and opens Preferences > MIDI Devices with a checklist.
5. Tick the checklist: `MIDIIN3` control-only, `Oxygen Pro 61` input + control, `MIDIOUT3` output. Remove any
   Mackie/HUI control surface that uses the Oxygen ports (Preferences > Control/OSC/web).
6. In the Helgobox window: **Menu > Instance > Enable global control** (once). Two ReaLearn units appear.
7. Restart REAPER. Within a few seconds the pads sweep green: the keyboard is in Live mode with software LEDs.

Check: press the Mode button until the SELECT LED is on, click a track in REAPER, its fader button lights.

## How it works

```
keyboard port 3  --CC/notes-->  REAPER (control-only input)  -->  ReaLearn unit "oxygen-pro-61/live"
      ^                                                                  |  targets: tracks, FX, transport,
      |  LED / pad colours (CC 32-39, note-on ch 1)  <---- feedback -----+  actions, compartment parameters
      |
   sysex 6D=2 (Live mode), 6B=1 (LED control), 6C=3 (software LEDs)
      ^
   Live watcher (ReaScript defer loop, started by __startup.lua)
      ^  echoes on the port-1 input: DAW button, encoder press, Back, Bank
      +------------------------------------- ReaLearn "SendMidi -> InputDevice" mappings
```

- `realearn/presets/main/oxygen-pro-61/live.preset.luau` is the whole layout: one ReaLearn main preset written in
  Luau (about 660 mappings generated from helpers). Bank, Mode, knob function, pad mode, layout and the Back layer
  are compartment parameters; groups and `Modifier`/`Bank` activation conditions select what is live.
- `reaper/Scripts/Oxygen Pro/Oxygen Pro - Live watcher.lua` polls for the `MIDIOUT3` device, sends the three
  sysex messages when the keyboard appears, then asks ReaLearn to repaint. It also does the things ReaLearn cannot:
  timed pad flashes (layout sweep, bank number, Back checkerboard) and tap tempo. Because REAPER's recent-input API
  cannot see control-only devices, ReaLearn echoes the relevant presses into the port-1 input for it.
- `realearn/presets/main/oxygen-pro-61/pads.preset.luau` is a second, small unit on port 1 that colours the pads by
  velocity when the keyboard is in Preset mode.
- `realearn/controllers.template.json` declares both units as managed controllers so they auto-load. Device numbers
  are machine-specific; the setup script rewrites them.

The measured protocol (sysex, message map, LED palette, firmware quirks) is in `docs/PROTOCOL.md`.

## Customising

Edit `live.preset.luau` and restart REAPER (or reload the preset in ReaLearn). The file is plain Luau with a
`mappings` table; the helpers at the top (`cc_button`, `note`, `paint`, `state_pad`, `action_pad`, `mixer_grid`,
`back_combo`) cover most needs. Action IDs are REAPER defaults; check yours in Actions > Show action list. Colours
must come from the 13-entry palette in `docs/PROTOCOL.md`; anything else shows as off.

To check a change compiles before restarting, run it through any Lua 5.4 / Luau interpreter:
`lua -e "dofile('live.preset.luau')"` (the file returns a table and uses no ReaLearn-only globals).

## Optional extras

None of these is needed for the integration to work.

- **`tools/` (Python 3 + `python-rtmidi`)**: `oxygen_led_unlock.py` sends the Live-mode sysex without REAPER
  (`--restore` hands the LEDs back to the firmware), `midi_capture.py` records both keyboard ports to a text file,
  `key_probe.py` shows which keystrokes the keyboard types for a Shift combination. To run them while REAPER holds
  the ports you need a multi-client MIDI stack (Windows MIDI Services on Windows 11, CoreMIDI on macOS); otherwise
  close REAPER first.
- **LoopCanvas layout (work in progress)**: the second layout's pad modes call `_LOOPCANVAS_*` actions for a looper
  that is not released yet. They are in the preset so the layout is ready when it ships; until then those pads do
  nothing and the DAW button still switches layouts. Replace the action names in `live.preset.luau` if you want
  the layout for something else.
- **`docs/legacy-*` and `tools/legacy/`**: the abandoned DAW-mode approach (User DAW preset built from the
  factory file), kept for anyone who needs the `.OxygenPro61DawPreset` byte layout.

## Known limits

- **No hold-modifiers.** The firmware reports nothing for a second button while any button is held. That is why
  Back is a press-then layer, and why Shift only does what M-Audio printed on the panel.
- **Shift + Tempo does nothing** in Live mode (no MIDI, no keystroke). Shift + << / >> type zoom keystrokes.
- **The OLED cannot be written** from the host in Live mode; it keeps saying Ableton. Pad sweeps replace it.
- **Live mode and the LED unlock are lost on power-off.** The watcher re-sends them within about two seconds.
- Faders and knobs are 7-bit in this mode. Knobs 1-4 with Shift edit the arpeggiator locally.
- Windows port names are hard-coded in two scripts.

## Repository layout

```
realearn/presets/main/oxygen-pro-61/   live.preset.luau, pads.preset.luau     -> Data/helgoboss/realearn/presets/main/oxygen-pro-61/
realearn/controllers.template.json      managed controllers                     -> Helgoboss/ReaLearn/controllers.json
reaper/Scripts/Oxygen Pro/              watcher, first-time setup, LED unlock, flash test -> Scripts/Oxygen Pro/
reaper/Scripts/__startup.oxygen-snippet.lua   the block install.ps1 appends to Scripts/__startup.lua
docs/                                   LIVE_MODE_MAP.md, oxygen_live_map.html (interactive), PROTOCOL.md, legacy DAW-mode notes
tools/                                  oxygen_led_unlock.py, midi_capture.py, key_probe.py; legacy/ has the abandoned DAW-preset builder
install.ps1                             copies everything into a REAPER resource folder
```

## Credits

- The M-Audio sysex commands were read from Ableton Live's `Oxygen_Pro` remote script; the LED palette, message map
  and firmware behaviour were measured on the keyboard with `tools/midi_capture.py`.
- ReaLearn by Benjamin Klum (helgoboss). REAPER by Cockos.
- Built by James Alexander with Claude, September 2026. MIT licence.

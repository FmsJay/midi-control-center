# Oxygen Pro 61 Rich REAPER Integration

Two-way integration of the **M-Audio Oxygen Pro 61** with **REAPER**, built on **ReaLearn** (Helgobox).
The keyboard runs in its Ableton "Live" firmware mode, which the host can unlock over sysex. In that mode every
control reports on one USB port, the fader-button LEDs and the sixteen RGB pads become writable, and REAPER's real
state drives them: what lights up is what REAPER says is true, never an echo of what you pressed.

**Interactive map of every control:** <https://fmsjay.github.io/oxygen-pro61-rich-reaper-integration/> (GitHub Pages build of `docs/oxygen_live_map.html`, which also opens straight from disk in any browser). Click Shift or Back on the drawn panel, switch Mode, Bank, DAW and pad modes like the hardware. Text version: `docs/LIVE_MODE_MAP.md`.

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
- **Off mode shows the keyboard's own toggles**: with no Mode LED lit, fader-button LEDs 1-4 mirror ARP, Latch, Chord and
  Scale, so an arpeggiator left on (which silences the keys while REAPER is stopped) is visible.
- **An editor inside REAPER** (ReaImGui) to remap everything, add layouts, pad modes, banks and latch modifiers, and apply
  without restarting. See *The editor* below.

## Requirements

| Piece | Tested with | Notes |
|---|---|---|
| REAPER | 7.79, Windows 11 | Any 7.x should work. macOS/Linux untested (port names differ, see below) |
| Helgobox (ReaLearn) | 2.18.2 | <https://www.helgoboss.org/projects/helgobox/> - install the VST3 or VST2 into REAPER |
| ReaImGui | 0.10 | only for the editor window; install via ReaPack |
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

## The editor (change anything without touching code)

`Scripts/Oxygen Pro/Oxygen Pro - Editor.lua` (registered as an action by the first-time setup script; needs ReaImGui)
opens a window with the keyboard drawn as it sits in front of you. Click any control and the inspector on the right
lets you set what it does:

- **Buttons** (transport, << >>, Bank, pad side buttons, encoder press, Back, DAW): nothing, a built-in function
  (transport, bank/pad-mode/layout stepping, tap tempo), any REAPER action picked with REAPER's own action picker
  or typed as a `_NAMED` command, or **modifier latch**: the button arms a layer and every other button can get a
  different function in that layer (the Layer combo). Any button can be a modifier; two at most.
- **Encoder turn**: browse tracks, zoom, or two actions (clockwise / anticlockwise).
- **Pads**: per layout and pad mode. A pad mode is drums, mixer (8 tracks mute/solo), free (one colour), or custom,
  where each pad is an action, a transport toggle or a track state toggle with its own colour and on-colour.
- **Fader banks** (up to 8): 8 tracks starting anywhere, focused FX, or free.
- **Layouts** (tabs): add as many as you like; the DAW button steps through them, the pad sweep colour is per layout.
- **Follow keyboard** makes the drawn panel track the real one: layout, pad mode, bank, Mode, knob function and
  armed layer update as you press buttons on the hardware.

**Apply** generates the ReaLearn preset from the model, backs up the previous one, writes it and reloads the
running unit in place, no REAPER restart. The first apply also keeps the original hand-written preset as
`live.preset.hand-written.luau`; **Restore hand-written** puts it back. **Save** stores the model as
`oxygen_editor/model.json` (loaded automatically next time), **Reset to default** returns to the shipped layout.
Ctrl+Z / Ctrl+Y undo and redo.

How it fits together: `oxygen_editor/model.lua` (the data model, validation, the default layout),
`generator.lua` + `interpreter.luau` (model -> ReaLearn Luau; the generated preset is the model literal plus the
interpreter, so ReaLearn, the editor and `tests/test_generator.py` run the same code), `apply.lua` (backup, write,
reload), `state.lua` (live state, replayed from the presses the preset echoes into the port-1 input).
`tests/test_generator.py` proves the default model behaves exactly like the hand-written preset.

Two things the editor cannot give you, because the hardware cannot: hold-modifiers (the firmware reports nothing
for a second button while one is held, hence the latch), and piano keys as controls (they are notes on port 1
and stay notes).

## Customising by hand

`live.preset.luau` is generated; edit `oxygen_editor/interpreter.luau` (the part after `local MODEL = ...`) for behaviour the
model cannot express, then Apply from the editor. `live.preset.hand-written.luau` is the original single-file preset
if you prefer that style. Action IDs are REAPER defaults; check yours in Actions > Show action list. Colours
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
reaper/Scripts/Oxygen Pro/              editor, watcher, first-time setup, LED unlock, flash test, dev hook -> Scripts/Oxygen Pro/
reaper/Scripts/Oxygen Pro/oxygen_editor/ model, generator, interpreter, apply, state, json (the editor's engine)
reaper/Scripts/__startup.oxygen-snippet.lua   the block install.ps1 appends to Scripts/__startup.lua
docs/                                   LIVE_MODE_MAP.md, oxygen_live_map.html (interactive), PROTOCOL.md, legacy DAW-mode notes
tools/                                  oxygen_led_unlock.py, midi_capture.py, key_probe.py; legacy/ has the abandoned DAW-preset builder
tests/test_generator.py                 offline proof that the generated preset equals the hand-written one (needs lupa)
install.ps1                             copies everything into a REAPER resource folder
```

## Credits

- The M-Audio sysex commands were read from Ableton Live's `Oxygen_Pro` remote script; the LED palette, message map
  and firmware behaviour were measured on the keyboard with `tools/midi_capture.py`.
- ReaLearn by Benjamin Klum (helgoboss). REAPER by Cockos.
- Built by James Alexander with Claude, September 2026. MIT licence.

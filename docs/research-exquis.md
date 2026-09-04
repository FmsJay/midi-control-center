# Intuitive Instruments Exquis — capability report for a REAPER/ReaLearn integration

Research date: 2026-09-04. Read-only research; nothing outside the scratchpad was modified.
Working copies of the primary documents were saved next to this report:

- `exquis_devmode_spec.pdf` / `.txt` — official "Developer Mode MIDI specification" (`Exquis_Dev_Mode_EN.pdf`, changelog "2025-03-10: Initial release"), from https://dualo.com/download/16645/
- `exquis_user_guide_3.0.0.pdf` / `.txt` — official standalone user guide 3.0.0, from https://dualo.com/download/12784/
- `exquis_user_guide_v2.pdf` / `.txt` — user guide V2.1.0 (Kraft Music mirror), https://files.kraftmusic.com/media/ownersmanual/Intuitive_Instruments_Exquis_User_Guide_v2.pdf

Legend: **[verified]** = read directly from a primary source; **[inferred]** / **[uncertain]** = my reading, not stated by a source.

---

## 0. TL;DR for the integration

1. The Exquis is a single USB-MIDI in/out pair named **"Exquis"** on Windows/macOS (DrivenByMoss discovers it by that name; Linux shows "Exquis MIDI 1") [verified: `ExquisControllerDefinition.java`]. There is only one port; notes and control share it.
2. The official host API is **Developer Mode** (firmware ≥ 2.1). Header `F0 00 21 7E 7F <cmd> … F7`. You enter it by sending a zone bit-mask (`F0 00 21 7E 7F 00 <mask> F7`) and leave with mask `00`. Taken-over zones stop working natively and instead report on **MIDI channel 16** (`9F/8F` pads, `BF` buttons/encoders/slider); LEDs of taken-over zones are set with sysex cmd `04` (RGB 0–127 + effect byte), or with CC/Note/PolyAT on channel 16 via a 128-entry palette [verified: dev-mode spec pp.1–7].
3. **Pads taken over = no MPE.** In Developer Mode a taken-over pad sends only Note On/Off `9F pad 7F` on ch 16, no pitch bend / CC74 / pressure [verified: spec p.6; forum thread 495, staff confirms "not possible to play in MPE in Dev Mode … designed for control"]. So the sensible design is to take over **encoders + slider + up/down + the six action buttons only** (mask `0x2E`, or `0x22` as DrivenByMoss does for play mode) and leave the pads native so they keep sending MPE on ch 2–15.
4. The standalone **Exquis app is not a controller editor for DAW use**. It is a JUCE-built host/looper (VST/VST3 hosting, 11 tracks, loops, snapshots, audio/MIDI export) that owns the port with the legacy WinMM API, drives the keyboard by sysex, and the vendor FAQ explicitly says it "is not designed to be used in conjunction with other applications or synthesizers" [verified: FAQ; exe strings]. Use it once to set layouts/CCs/curves (Menu > Standalone settings), then close it. No loopback port is needed for REAPER.
5. A complete open-source reference implementation already exists: **DrivenByMoss** (LGPLv3) supports Exquis in both Bitwig and its REAPER extension DrivenByMoss4Reaper (Exquis since v25.5.0, Reaper 7.22+; current 26.6.4 needs Reaper 7.55+). Its Java source is the best documented example of the protocol (below). ReaLearn can do the same thing with the Raw MIDI/SysEx source, MIDI-script (Luau) feedback and lifecycle actions.

---

## 1. Local sources on the drive

| Path | What it is |
|---|---|
| `J:\Portable Workstation\DAW\Programs\Exquis\Exquis.exe` | Installed Exquis app, **FileVersion/ProductVersion 3.0.0**, 34.7 MB, dated 2025-11-26 (VersionInfo read with PowerShell). Only the exe and Inno-Setup uninstaller (`unins000.*`) are in the folder — **no README, manual, PDF, changelog, HTML, JSON or MIDI chart ships with it.** |
| `…\Programs\Installs and Zips\exquis_2.0.0_setup.exe` / `.zip` | Older app installer, ProductVersion 2.0.0, CompanyName "Intuitive Instruments", 143 MB, 2024-12-20. |
| `…\Programs\Installs and Zips\Exquis_Firmware_Updater_2.0.0_win.zip` and `Exquis_Fw_Updater.exe` | Firmware updater 2.0.0 (exe ProductVersion 1.0.0.0). Zip contains `Exquis_Fw_Updater.exe`, `Resources/dfu-util.exe`, `Resources/H723ZETx.bin` (106,632 B, 2024-12-20 — the firmware image; the name is the STM32H723ZE MCU part), `Resources/libusb-1.0.dll`, `Resources/wdi-simple.exe` (libwdi driver installer). |
| `…\Programs\Resources\` | The same four Resources files unpacked (identical sizes/dates). |
| `…\Programs\usb_driver\` | libwdi-generated **WinUSB driver INF for `USB\VID_0483&PID_DF11`** = STMicroelectronics DFU bootloader (the DeviceName string "Microsoft XBox Controller Type S" is libwdi template boilerplate, not meaningful). This is the driver dfu-util needs to flash the Exquis on Windows. |
| `…\Firmware\` | Only the M-Audio Oxygen Pro 61 firmware; nothing Exquis-related. |
| Drive-wide glob for `*exquis*` | Only the files above (plus an unrelated Waves preset named "Exquisite…"). |

Strings extracted from `Exquis.exe` (grep of printable runs; the exe was **not** run):
- Build paths `C:\Users\IntuitiveInstruments\Documents\exquis\JUCE\modules\…` → the app is a **JUCE** application; it links `juce_audio_processors` (VST/VST3 hosting: "Scan for new or updated … plug-ins", "in VST3 format for Factory presets"), `juce_MPEInstrument`/`MPESynthesiser`, and `juce_Midi_windows.cpp` (`Win32MidiService`, i.e. the classic **WinMM** MIDI API).
- UI/help strings confirm the feature set: "Up to 11 tracks", loops ("length rounded up to the next 2^n"), snaps, metronome, quantization, "records the audio output of Exquis app … (.wav)", "Select a folder to export MIDI clips into", "Stops all notes on all MIDI channels (MIDI Panic)", "Another instance is running - quitting...", "This may be because another application is currently using the same device" (JUCE audio-device error text).
- French/English help text for the 4th encoder: "A click on the 4th encoder … freezes the held and modulated notes (X/Y/Z axes)…" (MPE Freeze).
- No sysex byte tables or port-name strings are visible in plain text.

---

## 2. Hardware summary

All from the User Guide 3.0.0 (pp.1–2, 4–6) unless noted.

- **Keys:** 61 backlit hexagonal soft-silicone keys ("pads"). Sensing per key: velocity ("strike **and lift** force" — i.e. release velocity too, added in 3.0.0 wording; V2.1.0 said only "strike force"), horizontal tilt = **X → Pitch Bend**, vertical tilt = **Y → CC#74**, pressure = **Z → Channel Pressure (MPE) or Polyphonic Aftertouch** [verified]. Hex layout: consecutive semitones horizontally, thirds vertically; default layouts in memory: 1 Exquis, 2 Exquis with duplicates, 3 Chromatic, 4 "4x4 for drums" (notes 36–51), 5 General MIDI percussion (35–81), 6 Rainbow (0–60). App stores up to 8 layouts and 32 scales on the device [verified: product page].
- **Pad numbering (for LEDs/dev mode):** 0 = bottom-left … 60 = top-right, "running across the rows" [verified: dev spec p.7; bjglover README]. Row structure is not stated in any source; 61 = 6+5+6+5+…+6 over 11 rows is a plausible reading **[inferred/uncertain]**.
- **Encoders:** 4 clickable rotary encoders with an RGB LED each ("light feedback").
- **Buttons:** 10 backlit action push buttons: Settings, Sound, Record, Loop, Clips, Play/Stop, Down, Up, Undo, Redo (names from the dev-mode ID table, p.7). Physical layout: the ten buttons are at the bottom [user guide "from bottom to top: 10 buttons, slider, 61 keys, 4 encoders"].
- **Slider:** 1 continuous capacitive touch strip divided into **6 zones**, each with an LED.
- **LEDs:** RGB under every pad, every button, every slider zone and every encoder. Host colour resolution is 7-bit per channel (0–127 R,G,B) via sysex; also a 128-entry palette [verified: dev spec]. "High-brightness LEDs (outdoor/stage)" [product page]. Brightness is a keyboard setting (Settings 1, encoder 7).
- **Display:** none. Numbers (tempo, firmware version, channel counts) are shown by lighting hexagons [user guide p.5/6; welcome page].
- **Ports:** USB-C (power + MIDI); MIDI IN and MIDI OUT on 3.5 mm **TRS Type A** (two adapters supplied; Type B incompatible); CV 0–5 V GATE / PITCH / MOD 3.5 mm outs (monophonic X→PITCH, Z→MOD) [verified: guide p.2; product page]. Kensington Nano slot. Power 5 V / 0.9 A max, ~4.5 W [guide p.2; product page].
- **MIDI THRU:** the device does **not** implement general MIDI Thru; only **CC#64, CC#11, CC#65, CC#67** received on MIDI IN are forwarded to USB and MIDI OUT (pedal support, firmware ≥ 2.2) [verified: guide p.2; FAQ].
- **MIDI Score display:** independent of Developer Mode, Note On/Off received **on channel 1 via USB** (or MIDI IN) lights the matching pads green; out-of-range notes light the octave button [verified: dev spec p.7; guide p.7].
- **Editions:** Pure (317×146×36 mm, 0.52 kg) and Deluxe (317×165×36 mm, 0.75 kg, wood/metal/cork trims) [product page]. MCU: STM32H723 (from firmware file name) **[inferred]**.

---

## 3. What the device SENDS by default (standalone / non-Developer mode)

Source: User Guide 3.0.0 pp.4–6 unless noted.

### 3.1 Notes / MPE
- Two modes, switched in **Settings (2) → encoder 1 click**:
  - **MPE (blue LED):** X/Y/Z per key, one note per channel. **Channel 1 = master/global** (CCs from encoders/buttons, PC). Encoder turn sets the number of **member channels 1–14**; "A setting of 14 is recommended". **"Channel 16 is used for communication with DAWs (e.g. Remote Script for Ableton Live)"** — so with 14 members the note channels are 2–15 [verified guide p.6; FAQ].
  - **Poly aftertouch (yellow LED):** single selectable channel 1–16, Z as Polyphonic Key Pressure.
- **Per-note pitch-bend range** (Settings 2, encoder 2): expressed in **48ths of the synth's range**; either set synth to ±48 and choose the Exquis value, or set Exquis to 48 and choose on the synth. Effective semitones = Exquis × synth / 48 [guide p.6; FAQ]. In CV the value is semitones.
- Y axis is always **CC#74** (per-note in MPE, on the note channel). Z is Channel Pressure (MPE) or Poly AT.
- Octave buttons transpose ±12; Transpose setting (Settings 1) shifts by semitones. The lowest note number of the default layout is not stated in the guides; DrivenByMoss maps grid index 0 to note 36 when *it* reprograms the pads, which is its own choice, not the factory layout **[uncertain]**.
- **MIDI clock out**: USB / DIN / both / none (Settings 1, encoder 1). Internal tempo 120 default; it **follows incoming MIDI clock** on USB or DIN. Play/Stop button sends MIDI clock start/stop ("MIDI clock play (green) / stop (orange)") [guide p.4/5].
- Arpeggiator (slider sets rate 1/4 … 1/24; pattern chosen in Settings 1) and **Freeze** (4th-encoder click) are generated on the device and output as ordinary notes.

### 3.2 Buttons and encoders (default CCs, standalone)
Guide 3.0.0 p.4 numbering (the mapping of the numbered callouts to physical labels is not captured in the extracted text — the figure was an image; treat the physical assignment as **[uncertain]**):
- Item 1: Settings (1) (hold) — keyboard settings menu. Item 2: Settings (2) (hold) — MIDI & layout settings. (These are the "Settings" and "Sound" buttons of the dev-mode table **[inferred]**.)
- Item 3: **CC#32, click to activate (toggle)**; item 4: **CC#33, hold to activate (momentary)**; item 5: **CC#34, hold** — "Default values are editable in the Exquis app: Menu > Standalone settings". (Likely Record/Loop/Clips **[inferred]**.)
- Item 6: MIDI clock play/stop (Play/Stop button). Item 7: Octave up/down buttons. Undo/Redo buttons: no standalone function is described **[uncertain]**.
- Item 8: Slider = arpeggiator speed.
- Items 9–12 = the four encoders: **encoder 1 = CC#41 (click CC#21), encoder 2 = CC#42 (click CC#22), encoder 3 = CC#43 (click CC#23), encoder 4 = CC#44 (click = Freeze, no CC)**. Defaults editable in the app.
- Whether the standalone encoder CCs are absolute or relative is **not stated** anywhere I found **[uncertain]**; Omnisphere's hardware guide maps "Knob 1–4 (CC#14–17)" as "factory default", which contradicts the user guide (CC41–44) — probably an app-side profile or an older firmware default **[uncertain]** (https://support.spectrasonics.net/manual/Omnisphere3HW/3/en/topic/setting-up-the-exquis).
- FAQ tips: assign CC64 to a button to use it as sustain, CC123 to an encoder click for panic.
- DrivenByMoss defines an extra dev-mode command `0x0A CMD_ENCODERS_SNAPSHOT` "Get the non developer mode CC numbers configured by users" — **not in the published spec** (2025-03-10); presumably added in a later firmware/spec revision **[uncertain]**.

### 3.3 What is configurable in the app
Menu > Standalone settings: CCs for encoders/buttons (record, loops, snaps…), sensitivity curves, trigger threshold, up to 8 note layouts and 32 scales stored on the device, per-key colour/value editing (announced end-2024), microtonality [product page; FAQ; forum 377]. On the keyboard itself: MPE/PolyAT + channel count, PB range, layout, scale (14 built-in: Major, Natural Minor, Melodic Minor, Harmonic Minor, Dorian, Phrygian, Lydian, Mixolydian, Locrian, Phrygian dominant, Major Pentatonic, Minor Pentatonic, Whole Tone, Chromatic), tonic, transpose, clock routing, tempo, brightness/threshold (default 50 in 3.0.0, was 20 in 2.1.0). Settings persist across power cycles; **factory reset = hold encoder 2 click while plugging in**; **firmware version = hold Settings, then also Settings (2)** → green hexagons top/middle/bottom = major.minor.patch [guide p.5/7; welcome page; FAQ].

---

## 4. What the host can SEND — Developer Mode (official API)

Source: `Exquis_Dev_Mode_EN.pdf` (https://dualo.com/download/16645/), "This is the API used by the official Exquis MIDI Remote Script for Ableton Live." Requires firmware ≥ 2.1 (gearnews: "firmware version 2.1 added poly-hold sustain and developer mode"). Device answers **only on the USB-MIDI port**.

### 4.1 Sysex frame
```
F0 00 21 7E 7F <id> [...] F7
```
Manufacturer ID `00 21 7E` (Dualo), then a fixed `7F`, then the command id. All commands except `00` only work while Developer Mode is active.

| id | Command | Request | Response |
|---|---|---|---|
| `00` | **Setup Developer Mode** | `F0 00 21 7E 7F 00 mask F7` | none |
| `01` | Use custom scale list | `F0 00 21 7E 7F 01 [count] F7` (omit count → revert to internal list) | none; afterwards each scale change makes the device send cmd 07 with the index |
| `02` | Colour palette | get all: `… 02 F7`; get one: `… 02 index F7`; set: `… 02 start_index r g b [r g b …] F7` | get all → `… 02 color(0)…color(127) F7` (3 bytes each); get one → `… 02 index r g b F7` |
| `03` | Refresh | `… 03 [settings_page] F7` — sent by either side to request an LED refresh; **the device sends it when entering (`7F`) / leaving the settings menu** (page number) | none |
| `04` | **Set LED colour** | `F0 00 21 7E 7F 04 start_id  r g b fx  [r g b fx …] F7` — contiguous run of LEDs starting at `start_id`, **4 bytes per LED**: R,G,B 0–127 + effect byte | none |
| `05` | Tempo | get: `… 05 F7`; set: `… 05 msb lsb F7` (BPM 20–240; msb = bit 7, lsb = low 7 bits; 120 = `00 78`, 200 = `01 48`); device sends it when tempo changed in settings | `… 05 msb lsb F7` |
| `06` | Root note | get `… 06 F7`; set `… 06 note F7` (0=C … 11=B); device sends on change | `… 06 note F7` |
| `07` | Scale number | get `… 07 F7`; set `… 07 scale F7` (0–127); device sends on change | `… 07 scale F7` |
| `08` | Custom scale | get `… 08 F7`; set `… 08 d0 … d11 F7` (12 × 0/1 degree flags), valid for the duration of dev mode | `… 08 d0…d11 F7` |
| `09` | Snapshot | get `… 09 F7`; restore `… 09 <255 bytes> F7` — saves/restores current layout + MIDI settings (used per-track by the Ableton script and DrivenByMoss) | `… 09 <255 bytes> F7` |
| `0A` | (undocumented) encoders snapshot — from DrivenByMoss source only **[uncertain]** | | |

### 4.2 Zone mask for cmd 00
| bit | mask | zone |
|---|---|---|
| 0 | `01` | Pads |
| 1 | `02` | Encoders |
| 2 | `04` | Slider |
| 3 | `08` | Up/Down buttons |
| 4 | `10` | Settings/Sound buttons |
| 5 | `20` | All other buttons (Record, Loop, Clips, Play/Stop, Undo, Redo) |

Add masks to combine (`2F` = everything except Settings/Sound). "Once a zone is taken over … Exquis will stop processing its inputs normally (except during native menu interaction in the case of the Settings/Sound buttons). Instead, it will directly send input events through USB-MIDI, and it will accept LED control messages related to it." Exit: mask `00`. DrivenByMoss constants: `DEV_MODE_OFF=0x00`, `DEV_MODE_PLAY_MODE=0x22` (encoders + other buttons), `DEV_MODE_FULL=0x3F`; it sends `00` on shutdown.

### 4.3 Element / LED identifiers (decimal)
| id | element |
|---|---|
| 0–60 | Pads (0 = bottom-left, 60 = top-right) |
| 80–85 | Slider zones 1–6 (LEDs) |
| 90 | Slider position (input only; 127 = untouched) |
| 100 Settings · 101 Sound · 102 Record · 103 Loop · 104 Clips · 105 Play/Stop · 106 Down · 107 Up · 108 Undo · 109 Redo | buttons |
| 110–113 | Encoders 1–4 |
| 114–117 | Encoder push buttons 1–4 (the spec table says "114..118, count 4" — an off-by-one in the PDF; DrivenByMoss uses 0x72–0x75 = 114–117) |

### 4.4 LED effect byte (`fx`, used in cmd 04 and in the PolyAT channel message)
`00` none · `3F` pulsate to black · `7F` pulsate to white · `3E` pulsate to red · `7E` pulsate to green · `00`–`3D` alpha (opaque → transparent) · `40`–`7D` blend to white (0 → 100 %). Pulsing is synced to the device tempo (which you can set with cmd 05).

### 4.5 Channel-16 messages (both directions, only for taken-over zones)
Out to device:
- `BF id palette_index` — set LED colour from the palette (CC on ch 16, CC number = element id).
- `9F pad vel` / `8F pad` — Note On/Off on ch 16 may also be used to colour a **pad** (velocity = palette index).
- `AF id fx` — Poly Aftertouch on ch 16 sets the LED effect.

In from device:
- Pad pressed `9F pad 7F`, released `8F pad 00` (pad 0–60). **Fixed velocity, no X/Y/Z.**
- Button pressed/released `BF button 7F` / `BF button 00` (100–109), same for encoder buttons (114–117) and slider zones (80–85).
- Encoder turned `BF encoder delta` (110–113), **relative, offset-binary: steps = delta − 64** (DrivenByMoss: `RelativeEncoding.OFFSET_BINARY`, `OffsetBinaryRelativeValueChanger(128,1)`).
- Slider touched `BF 90 portion` (0–5, 127 = released).
- Sysex notifications: cmd 03 (refresh, when the user enters/leaves settings), 05/06/07 when tempo/root/scale change in the settings menu.

### 4.6 Not available
- No text/display commands (no display). No "mode change" command other than the zone mask; scale/root/tempo/snapshot are the only state you can push. Note **remapping pads to notes is not part of this spec** (forum 488 complains about exactly that) — layouts are done in the app or via the 255-byte snapshot blob (opaque).
- MPE while pads are taken over: not possible (forum 495, staff, 2026-02-17: "we are currently working on improving it").

### 4.7 The older "slave mode" protocol (pre-2.1, probably obsolete)
Documented by Intuitive Instruments' own `MAX_KeyRemapper` (GPL-3.0, last push 2024-08-29) and reverse-engineered by bjglover (Feb 2024) / jackmau (May 2024): keep-alive `F0 00 21 7E F7` every ≤300 ms puts the device in "slave mode"; `F0 00 21 7E 04 keyId note F7` remaps a key; `F0 00 21 7E 03 keyId r g b F7` key LED; `… 07 buttonId r g b F7` button LED; `… 09 knobId r g b F7` encoder LED; device sends `F0 00 21 7E 08 buttonId state F7`; standard scale colours `38 1D 41` and `7F 5F 3F`; G/B values > 79 reportedly misbehave. A user on firmware 3.0.0 could not get these to work and noticed they don't match the official spec [forum 488]. Treat this protocol as **legacy/likely removed [uncertain]**; use the `7F`-prefixed Developer Mode API.

---

## 5. The standalone Exquis app (3.0.0) and port sharing on Windows

- **What it is:** a JUCE standalone host/looper: hosts VST/VST3 (AUv3 on mac), up to 11 layered tracks, up to 4 loops per track (2^n bars), snapshots, metronome/quantize, sensitivity-curve editor, layout/scale/CC editor, preset library (2,000+ presets for Surge XT, Vital, Decent Sampler, Pigments, Omnisphere 3, SWAM, Serum, Pianoteq…), audio (.wav) recording and MIDI (.mid) export, "Score display on Exquis keyboard", "MPE Freeze" [product page; welcome-page 3.0.0 release notes; exe strings]. It is **not** a control-surface editor and does not act as a MIDI router.
- **App ↔ keyboard:** when connected to the app "the Exquis keyboard is in MPE mode, the buttons and rotary encoders do not send MIDI CC, and there may be conflicts" — the app drives them by sysex [FAQ; forum 323 staff: "for now we use SysEx messages"]. "Currently, the Exquis application is not designed to be used in conjunction with other applications or synthesizers" — recommended workaround: configure scales/layouts in the app, then disconnect [FAQ https://dualo.com/en/help-faq/].
- **Port exclusivity:** the app uses JUCE's `Win32MidiService` (WinMM). On the classic Windows MIDI stack a WinMM client holds a port exclusively, so the app and REAPER cannot both open "Exquis" [general Windows behaviour; JUCE strings in exe]. bjglover documented that to sniff the app he had to point the app at a **loopMIDI** port and relay to the hardware with MIDI-OX/Bome [bjglover README]. Windows MIDI Services (Windows 11, 2025+) makes endpoints multi-client, which *may* lift this for both apps; unverified for this pairing **[uncertain]**.
- **Coexistence recommendation:** don't try to run both. Use the app only to store layouts/CCs/curves on the device, quit it, then let REAPER own the port. A virtual port is only needed if you insist on the app's synth engine and REAPER simultaneously, and even then the app's sysex traffic would fight your ReaLearn LED writes.
- **Versions/downloads (https://dualo.com/en/welcome/):** app 3.0.0 Windows (`exquis_3.0.0_setup.zip`, 765 MB, https://dualo.com/download/12823/), mac (…/12819/); firmware 3.0.0 updater Win (`Exquis_Fw_Updater3.0.0_Win.zip`, …/13196/), mac (…/13200/), Linux CMD (…/19264/); user guide (…/12784/). 3.0.0 release notes: "Audio output recording – MIDI export – Score display on Exquis keyboard – MIDI CC support: CC#64, CC#11, CC#65, CC#67 – Scale and layout selection from Exquis keyboard – MPE Freeze – New presets." The drive currently holds firmware **2.0.0** and app **3.0.0** — the installed app is newer than the firmware image on disk; the device's actual firmware must be checked on the keyboard (Developer Mode needs ≥ 2.1, pedal thru ≥ 2.2).
- **Firmware update procedure** [welcome page; local zip contents]: hold **encoder 1's click while plugging in USB** (keyboard appears off = STM32 DFU bootloader, `VID 0483 PID DF11`), install the WinUSB driver (`wdi-simple.exe` / the `usb_driver` INF on the drive), run the updater which calls `dfu-util -d ,0483:df11 -a 0 -D H723ZETx.bin -s 0x08000000` (Linux instructions on the page state this command verbatim).

---

## 6. Existing integrations and licences

| Project | What | Licence | Notes |
|---|---|---|---|
| **DrivenByMoss** (Jürgen Moßgraber) — Bitwig extension + **DrivenByMoss4Reaper** | Full Exquis support: play view (native pads, MPE passed through), session view (clips/mixer on pads), knob modes (project/track/device params, volume), arpeggiator, transport buttons, per-track snapshot recall, tempo/root/scale sync both ways | **LGPLv3** (code https://github.com/git-moss/DrivenByMoss `LICENSE`; docs repo LGPLv3 too) | Exquis added 25.5.0 (Bitwig 5.3+, Reaper 7.22+); current 26.6.4 (2026-08-02) needs Reaper 7.55+. Since v26 it uses REAPER's native MIDI ports (enable them in REAPER prefs; tick "Do not send reset messages" on the output). Installs into `UserPlugins` (or `Plugins` for portable REAPER). Docs: https://github.com/git-moss/DrivenByMoss-Documentation/blob/master/Intuitive-Instruments/Exquis.md ; site https://www.mossgrabers.de/Software/Reaper/Reaper.html. Source files: `src/main/java/de/mossgrabers/controller/intuitiveinstruments/exquis/{ExquisControllerSetup,ExquisConfiguration,ExquisControllerDefinition}.java`, `controller/{ExquisControlSurface,ExquisPadGrid,ExquisColorManager,ISysexCallback}.java`. |
| **Exquis Ableton Live Remote Script** V1.0.7 (Intuitive Instruments) | Live 12 Session/Note/Track-Device modes, 366 presets grid, LED feedback; uses the Developer Mode API | **Unknown — not verified.** The 16 MB zip (`Exquis-Ableton-Live-Remote-Script-V1.0.7.zip`, https://dualo.com/download/16217/) was not downloaded (requires explicit permission); the web page states no licence. | Setup: "Select Exquis as Control Surface, Input, and Output" in Live; enable Track/Sync/Remote/MPE on input [https://dualo.com/en/daws-plugins/]. |
| **intuitiveinstruments/MAX_KeyRemapper** | Max 8 patch: key→note remap and LED colours via the legacy slave-mode sysex | **GPL-3.0** (GitHub API `license.spdx_id`) | Last push 2024-08-29; protocol probably superseded. Windows note in README: connect hardware, launch DAW, then the patch, "to avoid port conflicts". |
| **bjglover/Intuitive-Instruments-Exquis** | Python + python-rtmidi scripts (blank/green/rows/columns) using `F0 00 21 7E 03 key r g b F7` | **No licence file** (all rights reserved by default) | Port name seen by rtmidi on Windows: "Exquis 1" (may be "Exquis 2"). |
| **jackmau/Exquis** "Isomorphic Layout Programmer" | Python/tkinter layout + LED programmer (legacy protocol, 400 ms keep-alive) | **No licence file** | Credits Sergueï Bécoulet for sysex docs. |
| **Exquis Root & Scale Mode Sync** (Loopy Pro template, patchstorage) | Sends `F0 00 21 7E 7F 00 01 F7`, `F0 00 21 7E 7F 06 <root> F7` (or 07 scale), `F0 00 21 7E 7F 00 00 F7` on project load | **MIT** | Requires firmware ≥ 2; https://patchstorage.com/exquis-root-scale-mode-sync/ |
| Native support | Logic Pro (auto-detected), Cubase 14 | n/a | [daws-plugins page] |

Nothing Exquis-specific for **ReaLearn** exists publicly (forum search for "realearn" returns nothing).

---

## 7. Recommended REAPER / ReaLearn design (Oxygen-Pro-style two-way)

### 7.1 Ports and REAPER preferences
- Enable the single **"Exquis"** device in *Options > Preferences > MIDI Inputs* ("Enable input from this device") and *MIDI Outputs* ("Enable output to this device"). ReaLearn lists only devices enabled there [ReaLearn docs: input/output section].
- Keep the Exquis app closed. No LoopBe1/loopMIDI needed.
- If DrivenByMoss4Reaper is ever installed for comparison, don't run both on the same port at the same time (both want dev mode and both write LEDs).

### 7.2 One device, two roles — how to split notes from control
- ReaLearn unit: **Control input = MIDI device "Exquis"**, **Feedback output = MIDI device "Exquis"** (never FX output for feedback — docs' best practice).
- With a hardware device as control input, ReaLearn is a *global* filter: **matched events are eaten before REAPER's tracks, unmatched events are forwarded to tracks as usual** ("Let unmatched events through" default on; REAPER ≥ 6.36) [ReaLearn unit concepts, "Letting through MIDI events"]. So: write mappings **only for channel 16** (the dev-mode channel) and sysex; the MPE stream on ch 1–15 stays unmatched and reaches the instrument track normally. This is exactly DrivenByMoss's filter list (`8n/9n/An/Bn 40/Bn 4A/Dn/En` for n = 0..14 to the DAW; ch 16 to the surface).
- Instrument track input: "Exquis: all channels" (MPE) — set the synth's PB range to 48 and the Exquis PB setting to taste, or 48/48.

### 7.3 Entering/leaving Developer Mode
- Use ReaLearn **mapping lifecycle actions** (activation → send raw MIDI; deactivation → send raw MIDI) on one always-active mapping:
  - on activate: `F0 00 21 7E 7F 00 2E F7` (encoders `02` + slider `04` + up/down `08` + other buttons `20`; add `10` only if you also want Settings/Sound, which then only work inside the native menu) — **leave bit 0 clear so pads keep playing MPE**;
  - on deactivate: `F0 00 21 7E 7F 00 00 F7`.
- If you *do* want pad LEDs for a session/clip view (Launchpad-style), you must include bit 0 and accept that pads then emit only `9F pad 7F` on ch 16 (no expression) while that mode is active — toggle between masks `2E` and `2F` with a button mapping, like DrivenByMoss's Clips button does between Play and Session views **[design inference]**.
- Handle the device's **Refresh** (`F0 00 21 7E 7F 03 …`) — after the user leaves the on-device settings menu the LEDs are reset, so re-send your LED state (a Raw-MIDI/SysEx source mapping matching `F0 00 21 7E 7F 03` can trigger a "re-fire feedback" action, or simply re-send on a timer/ReaScript).

### 7.4 Control mappings (ch 16)
- Encoders: source **CC 110–113 on ch 16, character "Encoder (type 2 / offset-binary 64 = zero)"** — delta = value − 64. Encoder pushes: CC 114–117, button. Slider: CC 90 absolute 0–5 (127 = release) — treat as a 6-position selector or use zones 80–85 as buttons.
- Buttons: CC 100–109 (value 7F/00) → transport (105 play/stop, 102 record, 103 loop), 108/109 undo/redo, 106/107 down/up (bank/track scroll), 104 clips (view toggle). Note: 100/101 (Settings/Sound) are only yours if bit 4 is set.
- Optional: react to the device's tempo/root/scale sysex (`… 05/06/07 …`) with Raw-MIDI sources with variable bits, e.g. root note `F0 00 21 7E 7F 06 [0000 dcba] F7` → a REAPER action/script; push REAPER tempo to the device with a **MIDI: Send message** target pattern `F0 00 21 7E 7F 05 [0000 000i] [0hgf edcb a…]` — the two-byte MSB/LSB split (bit 7 in the first byte) needs ReaLearn's variable-bit letters across two bytes (`a`…`h` in the LSB byte, `i` in the MSB byte) — verify against the pattern docs before relying on it [ReaLearn mapping concepts, "Variable patterns"].

### 7.5 Feedback (REAPER state → LEDs)
Three mechanisms, choose per element:
1. **Palette CC (cheapest):** feedback via a plain CC source on ch 16, CC = element id, value = palette index 0–127 (`BF id idx`). ReaLearn's normal numeric feedback on a "CC value" source does this natively; you only need a palette that puts useful colours at known indices. Read the factory palette once (`F0 00 21 7E 7F 02 F7`) or write your own (`… 02 start r g b … F7`) in a lifecycle action. Pulse/alpha effects via PolyAT `AF id fx`.
2. **Direct RGB sysex (what DrivenByMoss uses):** Raw MIDI/SysEx source with feedback, pattern `F0 00 21 7E 7F 04 <id> [0rrr rrrr] [0ggg gggg] [0bbb bbbb] 00 F7` where you fix two channels and vary one for a brightness bar, or better a **MIDI Script (Luau) source** that returns `{ address = id, messages = { {0xF0,0x00,0x21,0x7E,0x7F,0x04,id,r,g,b,fx,0xF7} } }` using `context.feedback_event.color` set from the Glue section's colour (this is the documented pattern in ReaLearn's "MIDI source script" example 3). One script can also batch a contiguous run of LEDs (e.g. all four encoder rings, or slider zones 80–85) in a single message.
3. **MIDI Score (green only, no dev mode):** send Note On/Off on **ch 1** to light pads for what a track is playing — handy for a "what is REAPER playing" view without taking over the pads.

Keep the LED write rate modest (61+ elements × 12 bytes at 31.25 kbit/s on DIN doesn't apply on USB, but the device also processes the palette; DrivenByMoss throttles with a 100/200 ms surface flush).

### 7.6 Pitfalls
- Firmware on the keyboard must be ≥ 2.1 (dev mode) — the drive only carries the 2.0.0 updater; fetch 3.0.0 from the welcome page.
- Dev-mode pads = no expression; don't take over bit 0 in the performance layout.
- The Exquis app rewrites LEDs and swallows CCs when it is running; close it.
- ReaLearn eats *matched* ch-16 traffic globally — fine — but be careful not to write a mapping that matches ch 1–15 notes (e.g. a "Note velocity, any channel" source) or your instrument track goes silent.
- The device sends `Refresh` when leaving its settings menu and resets LEDs; handle it.
- Send mask `00` on project close/ReaLearn unload (deactivation lifecycle action) or the buttons stay dead until power-cycle.
- The 255-byte snapshot blob is opaque; storing/restoring per-track layouts is possible but format is undocumented.
- Spec typo: encoder buttons are 114–117 (not 118).
- Unknowns still to verify on hardware: whether cmd 04 for pad LEDs works when pads are *not* taken over (spec wording implies not); standalone encoder CC absolute vs relative; exact physical button ↔ CC32/33/34 mapping.

---

## 8. Source index

- Dev-mode spec PDF: https://dualo.com/download/16645/ (linked from https://dualo.com/en/exquis-resources/, CC BY-NC-SA for the resources page assets)
- User guide 3.0.0: https://dualo.com/download/12784/ ; V2.1.0 mirror: https://files.kraftmusic.com/media/ownersmanual/Intuitive_Instruments_Exquis_User_Guide_v2.pdf
- Welcome/downloads/firmware: https://dualo.com/en/welcome/ ; FAQ: https://dualo.com/en/help-faq/ ; product page: https://dualo.com/en/exquis/ ; DAW scripts: https://dualo.com/en/daws-plugins/ ; Ableton script page: https://dualo.com/en/ableton-live-remote-script/
- Forum (Discourse JSON): https://dualoforum.intuitive-instruments.art/t/495 (Dev Mode entering), /t/488 (Linux remap, legacy vs new spec), /t/377 (dedicated CC mode), /t/268 (default CCs), /t/228 (MIDI In function), /t/323 (encoders with app open), /t/448 (Bitwig script), /t/464 (lights out)
- News: https://sonicstate.com/news/2025/09/08/exquis-mpe-controller-updated ; https://www.gearnews.com/intuitive-instruments-exquis-synth/
- DrivenByMoss: https://github.com/git-moss/DrivenByMoss (LGPLv3), docs https://github.com/git-moss/DrivenByMoss-Documentation (Intuitive-Instruments/Exquis.md, Reaper/Changes.md, Installation.md), https://www.mossgrabers.de/Software/Reaper/Reaper.html
- Other repos: https://github.com/intuitiveinstruments/MAX_KeyRemapper (GPL-3.0), https://github.com/bjglover/Intuitive-Instruments-Exquis (no licence), https://github.com/jackmau/Exquis (no licence), https://patchstorage.com/exquis-root-scale-mode-sync/ (MIT)
- Omnisphere 3 Exquis setup: https://support.spectrasonics.net/manual/Omnisphere3HW/3/en/topic/setting-up-the-exquis
- ReaLearn docs: https://docs.helgoboss.org/realearn/further-concepts/mapping.html#raw-midi-pattern (pattern syntax), …/further-concepts/source.html (MIDI source script), …/sources/midi/raw-midi-sysex.html, …/sources/midi/midi-script.html, …/targets/midi/send-message.html, …/further-concepts/unit.html (letting MIDI through), …/user-interface/main-panel/input-output-section.html, …/best-practices.html
- Local: `J:\Portable Workstation\DAW\Programs\Exquis\Exquis.exe` (3.0.0), `…\Programs\Installs and Zips\*Exquis*`, `…\Programs\Resources\`, `…\Programs\usb_driver\usb_device.inf`

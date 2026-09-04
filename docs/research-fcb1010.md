# FCB1010 as a true hold ("shift") pedal for REAPER/ReaLearn — research report

Date: 2026-09-04. Scope: Behringer FCB1010, stock firmware V2.5, one footswitch that must emit one MIDI message on press and a different one on release. Other switches stay on Program Change 0–99.

Certainty markers: **[confirmed]** = stated by a primary source (manual, firmware author's docs, or code on disk); **[corroborated]** = multiple secondary sources agree; **[uncertain]** = single or conflicting sources, verify with a MIDI monitor.

---

## 1. Bottom line

- **Stock V2.5 can do it, with exactly one message type: NOTE.** A preset with the NOTE function enabled sends Note On (velocity fixed, 64 per Behringer / 100 per the UnO editor manual — conflict, see §3.2) on press and Note Off — transmitted as Note On velocity 0 — on release. Program Change and Control Change messages on stock firmware fire on press only; there is no CC-on-release in the stock firmware at all. **[confirmed]**
- Program the shift switch as a preset with PC1–5 and CNT1/CNT2 disabled, NOTE enabled, on its own MIDI channel. ReaLearn sees it with a *Note velocity* source (Button character): 100 % on press, 0 % on release. Drive a ReaLearn compartment parameter in Absolute/Normal mode and use "When modifiers on/off" on the shifted mappings.
- Three stock-firmware side effects must be managed (§3.4): expression pedals are dead while any footswitch is held; the shift preset also *sets* the EXP A/B and relay state, so it must carry the same EXP settings as your PC presets or it will silence the pedals; and a NOTE preset double-tapped can emit a tap-tempo CC on CNT1's controller if CNT1 is enabled (keep CNT1 disabled).
- If you want it cleaner (LED shows hold state, pedals live while held, CC instead of note): UnO firmware €26 (momentary CC effect, but only in "stompbox mode" which reorganises banks to 19×5), or UnO2 €50 (any message on press/release, no bank restructuring), or FCB-505 €26 (every switch becomes CC 127/0 press/release on ch 13 — no programming, no PCs). Prices read from shop.fcb1010.eu on 2026-09-04.

---

## 2. What the local tools say (both are SysEx dump editors, not behaviour docs)

### 2.1 fcbtool (C) — `J:\Portable Workstation\DAW\Utility\fcbtool`
Files: `src/fcb.h`, `src/fcb.c`, `docs/fcb1010_dump_format.txt`, `README.md`. MIT licence (Jason March, 2024); "C implementation of Brian Walton's (brian@riban.co.uk) [Python] with slight mods to some errors noticed in sysex files".

Per-preset model (`FCB1010Preset` in `fcb.h`): `pc1..pc5_enabled/_program`, `cc1/cc2_enabled/_controller/_value`, `switch1_enabled`, `switch2_enabled`, `expA/expB_enabled/_controller/_min/_max`, `note_enabled`, `note_value`. Global (`FCB1010`): ten MIDI channels (`pc1..pc5`, `cc1`, `cc2`, `expA`, `expB`, `note`), `direct_select`, `running_status`, `merge`, `switch1`, `switch2`, exp A/B calibration.

Dump layout decoded by `parse_sysex()` (`fcb.c`):
- Dump is exactly 2352 bytes: `F0 00 20 32 01 0C 0F … F7`.
- **Enable flags** start at byte 14, bit-packed 7 bits per byte; after bit 6 the parser jumps `offset += 8` (the 8th byte of each group is padding). 16 flags per preset in this order: PC1, PC2, PC3, PC4, PC5, CC1, **SWITCH1**, CC2, **SWITCH2**, EXPA, (unused), (unused), EXPB, (unused), (unused), NOTE. All are stored *inverted* (bit set = disabled) **except** SWITCH1 and SWITCH2, which are stored non-inverted. This is the "some controls, such as switches, may be encoded inversely" remark in `docs/fcb1010_dump_format.txt`.
- **Values** start at byte 7, 16 data bytes per preset with every 8th byte skipped (`if ((offset-6) % 8 == 0) offset++`): PC1..PC5 program, CC1 ctrl, CC1 value, CC2 ctrl, CC2 value, EXPA ctrl/min/max, EXPB ctrl/min/max, NOTE number.
- Global bytes: channels at 2311–2317 (PC1–5, CC1, CC2), 2319 EXPA, 2320 EXPB, 2321 NOTE; `direct_select = data[2330] & 2`, `running_status = data[2330] & 4`, `merge = data[2330] & 16`, `switch1 = data[2334] & 4`, `switch2 = data[2329] & 64`, calibration 2343–2346.

What the tool does **not** model: there is no field for a release value, a second CC value, toggle/momentary mode, or note velocity. The only "switch" fields are the two **relay-jack** outputs (SWITCH 1 / SWITCH 2 on the rear panel), not a momentary/toggle mode for MIDI. The UI (`ui_ncurses.c` lines 142–158) just prints `NOTE: On/Off <n>`, `Switch 1: On/Off`, `Direct Select: Yes/No`.

CSV format (`write_csv()` / `load_csv()`): three header lines, then 100 preset rows. Third-line column names (0-based index):
```
0 Bank, 1 Preset,
2 Enabled, 3 Program            (PC1)   … 10 Enabled, 11 Program (PC5)
12 Enabled, 13 Controller, 14 Value     (CC1)
15 Enabled, 16 Controller, 17 Value     (CC2)
18 Enabled                              (Switch 1 relay)
19 Enabled                              (Switch 2 relay)
20 Enabled, 21 Controller, 22 Minimum, 23 Maximum   (Expression Pedal A)
24 Enabled, 25 Controller, 26 Minimum, 27 Maximum   (Expression Pedal B)
28 Enabled, 29 Value                    (Note)
```
Second line `MIDI Channel,,<PC1>,,<PC2>,,<PC3>,,<PC4>,,<PC5>,,<CC1>,,,<CC2>,,,N/A,N/A,<ExpA>,,,,<ExpB>,,,,<Note>,` — columns 2,4,6,8,10,12,15,20,24,28. Channel values are the raw dump bytes 0–15 **[uncertain whether 0 = channel 1; the sample CSV on disk uses 0..4, which reads as 0-based]**.

### 2.2 fcb1010 (Python) — `J:\Portable Workstation\DAW\Utility\fcb1010`
Files: `fcb1010.py`, `README.md`, `FCB1010.csv`, `FCB1010.ods`. README: "works with standard FCB1010 V2.5 firmware. It has not been tested with other versions … nor any third party firmware"; "only MIDI channel data is set in the FCB1010 when sysex is received" (i.e. sending a dump does not change direct-select/merge/etc. — matches the Behringer-firmware bug noted by the UnO editor manual, §4.3).

Same byte map and same CSV headers as fcbtool (fcbtool is a port). It has no concept of toggle/momentary/note-off either.

### 2.3 Where the two disagree (or are both wrong)
- **Python bug:** `parse_sysex` stores the note number into `self.preset[i].note` (line 168) but `save()`, `show_config()` and `get_raw_sysex()` use `.note_value` (lines 238, 283, 418; default 60 at line 44). A dump read from the pedal and then saved/sent will have every note reset to 60. fcbtool uses `note_value` throughout and does not have this bug. If you edit with the Python tool, set `note_value` yourself.
- **Global switch1 bit:** both read `data[2334] & 4` but write `data[2334] = 3; if switch1: |= 2` — read bit 2, write bit 1. Treat the global `switch1` field as unreliable in both tools (it is the latched/momentary relay setting, irrelevant to MIDI).
- **Filler bytes:** fcbtool writes 127 into 1835–2310 and forces `data[1838]=120`, `data[2322..2325]=127`, `data[2326]=120`, `data[2327..2328]=127`, `data[2350]=10`, and hard-codes calibration 0/127; Python writes 127 into 1839–2310, writes the calibration fields it parsed, and leaves the other bytes 0. The C author's comment says these were "errors noticed in sysex files (might be version differences?)". Neither is documented. Safest workflow: **dump from your own pedal, edit only the bytes/fields you need, send back** — do not generate a dump from scratch with either tool.
- Both tools default `expA_controller=27, expB_controller=7` (C `init_fcb1010`) — arbitrary defaults, not the factory ones.
- Neither tool can turn Direct Select on/off on the pedal (Python README; UnO ControlCenter manual p.18: "due to a bug in the Behringer firmware it is not possible to modify the other global settings through SysEx").

---

## 3. Stock firmware V2.5 behaviour

### 3.1 Per-preset message types and what fires on release
| Function | Panel switch | Press | Release | Source |
|---|---|---|---|---|
| PRG CHG 1–5 | 1–5 | Program Change (value 0–127, shown 1–128) | nothing | manual p.10–12 (manualslib), UnO guide p.7 |
| CNT 1, CNT 2 | 6, 7 | one CC each, fixed value | nothing | comparison PDF; Loopy Pro forum |
| EXP A, EXP B | 8, 9 | preset *enables/disables* the pedal and sets its CC number and min/max; pedal then streams CC on movement | n/a | manual p.13 |
| NOTE | 10/0 | Note On, note number 0–127 | **Note Off (Note On, velocity 0)** | UnO ControlCenter manual p.7; KVR owners; Gearspace |
| SWITCH 1/2 | 1, 2 (first page) | relay jacks set on/off (latched) or closed while held (momentary, global setting) | opens if momentary | UnO guide p.4; ControlCenter manual p.18 |

Message order on press: **PC1, PC2, PC3, PC4, CC1, CC2, PC5, NoteOn** (UnO ControlCenter manual p.7 — describes the stock unit). **[confirmed by firmware author]**

The "toggle" that stock firmware has for CC is *latching*, not momentary: if CNT1 and CNT2 use the same CC number on the same channel, the pedal sends the two values alternately on successive presses instead of both at once (comparison PDF, "BEHRINGER" column; Loopy Pro forum "set both to the same CC# with values of 0 & 127"). Nothing is sent on release. **[confirmed]**

So the only press+release pair on stock firmware is Note On / Note Off. **[confirmed]**

### 3.2 The NOTE message, exactly
- Status `9n` (n = NOTE channel − 1, set globally), data = note number (0–127), velocity fixed. Release: `9n <note> 00` (Note On with velocity 0, which is Note Off per MIDI spec). Running Status is a global option; when on, the release message may arrive as just `<note> 00` after the press message — any MIDI driver reconstructs this, ReaLearn will not notice. UnO ControlCenter manual p.7: "the floorboard always sends a NoteOn message on switch press, and a NoteOff message on switch release. (…the NoteOff message is actually a MIDI NoteOn with velocity 0…)". **[confirmed]**
- Velocity: Behringer manual p.17 (manualslib 1296932): "notes are always transmitted with a velocity of 64". UnO ControlCenter manual p.19: "With the stock FCB1010, all transmitted Note messages have a fixed velocity of 100." **[conflict — irrelevant for a Button source, but check on a MIDI monitor if you ever key on velocity]**
- Can a preset send ONLY a note? Yes — each of the 8 messages has its own enable bit (fcbtool flag map; manual p.11 "Enable/disable specific MIDI functions by keeping the corresponding foot switch pressed (about 1.5 s)"). **[confirmed]**
- Does it also send the preset's PCs? Only if their enable bits are on; disable PC1–5 and CNT1/2 in that preset. **[confirmed]**
- Channel: one global NOTE channel shared by every preset's note (global setup, footswitch 10). **[confirmed]**
- One note per preset; note number is the only per-preset parameter. **[confirmed]**

### 3.3 Direct Select mode
- Direct Select = presets chosen by typing two digits (bank then preset), so every preset needs two presses; the second press is the one that "selects". In this mode UP toggles relay SWITCH 1 and DOWN toggles SWITCH 2 (latched), and per-preset switch settings are ignored (UnO guide p.4; ControlCenter manual p.18; manual p.10 table 2.2). Tap-tempo does not work in Direct Select (manual p.14). **[confirmed]**
- Whether the note-off is tied to the release of the *second* press in Direct Select is not documented anywhere I found. **[uncertain]** For a hold pedal, keep Direct Select **off** (your PC 0–99 layout with UP/DOWN bank changes is the non-Direct-Select mode anyway).

### 3.4 Caveats for using a NOTE preset as a hold-shift
1. **Expression pedals freeze while a switch is held.** Comparison PDF, Behringer column: "While pressing a footswitch, expression pedals cannot be used" (UnO: "While pressing a footswitch (for instance used as keyboard damper pedal), expression pedals can still be used"). So shift+pedal-sweep is impossible on stock firmware. **[confirmed by firmware author]**
2. **The shift preset *sets* EXP A/B and relay state.** Stock presets have only on/off for each pedal ("Each patch can turn the 2 expression pedals off or turn them on with corresponding CC number" — comparison PDF; UnO adds "leave unchanged"). If the shift preset has EXP A/B disabled, pressing it switches the pedals off until the next preset that enables them. Program EXP A/B in the shift preset with the same CC numbers and ranges as your PC presets. Same logic for SWITCH 1/2 if you use the relay jacks. **[confirmed]**
3. **LED / display:** stock lights only the LED of the last preset pressed; pressing the shift preset moves the LED to it and it stays there after release; the display shows the shift preset's number. You lose the visual of which PC preset is current (Wikibooks; Loopy Pro forum "only 1 active LED which shows the last switch pushed"). There is no "held" indication. **[corroborated]**
4. **Tap-tempo CC:** pressing a NOTE preset twice makes the pedal compute a tap interval and, *if CNT1 is enabled in that preset*, send a CC on CNT1's controller number (manual p.14–15: NOTE and CNT 1 must both be enabled; value derived from the interval, max 1,270 ms; UnO added a global switch "to prevent unwanted CC messages"). With CNT1 disabled in the shift preset nothing extra should be sent, but the manual's wording is about setup, not a guarantee. **[uncertain — verify with a MIDI monitor by double-tapping the shift switch]**
5. **Re-pressing a preset re-sends** everything (stock has no "block repeated PC"; UnO adds it). Harmless for the shift preset (it only has the note).
6. **Bank position:** the shift preset lives in one bank. If you change banks with UP/DOWN, the shift switch in the new bank is a different preset — program the same NOTE preset into the same switch position in every bank you use (10 presets, one per bank), or keep everything in one bank. Because the NOTE channel is global, all ten can use the same note number.
7. **Firmware bugs:** MIDI merge is broken on stock (hanging notes when a keyboard is merged through MIDI IN while moving pedals; "flashing 88" at power-up with ActiveSense on MIDI IN). Do not route a keyboard through the FCB's MIDI IN. (comparison PDF) **[confirmed by firmware author]**
8. Global settings other than MIDI channels cannot be set by SysEx on stock firmware (ControlCenter manual p.18; Python README). Direct Select, merge, running status, relay latched/momentary must be set on the front panel.

---

## 4. Programming the shift preset on stock firmware

### 4.1 Front panel (Behringer manual, sections 3–4; manualslib pages 10–13; UnO guide steps mirror the stock flow)
Global first (only if the NOTE channel needs changing):
1. Hold **DOWN** while powering on (~2.5 s) → global setup; the DIRECT SELECT LED shows the mode (footswitch 10/0 toggles Direct Select — leave it **off**). Press **UP/ENTER** to go to the MIDI-function page.
2. On the MIDI-function page footswitches map to functions: 1–5 = PRG CHG 1–5, 6 = CNT 1, 7 = CNT 2, 8 = EXP A, 9 = EXP B, **10/0 = NOTE** (manual table 2.1). Press 10/0, enter the channel (1–16) with the footswitches, confirm with UP/ENTER. Pick a channel none of your PC presets use (e.g. 16) so ReaLearn can filter on channel alone.
3. Hold DOWN ~2.5 s to leave.

Preset:
1. Select the bank with UP/DOWN and press the footswitch you want as shift (say switch 10/0 of bank 0).
2. Hold **DOWN** > 2.5 s → PRESET programming; the green SWITCH 1/SWITCH 2 LED flashes. Footswitches 1 and 2 now toggle the two relay states; set them to whatever your PC presets use; confirm with **UP/ENTER**.
3. Now each footswitch LED shows whether that function is enabled. **Hold** a footswitch ~1.5 s to toggle its enable: make LEDs 1–7 **off** (PC1–5, CNT1, CNT2), LEDs 8 and 9 **on** if your other presets use the expression pedals (see §3.4 #2), LED **10/0 on** (NOTE).
4. Briefly press **10/0** → its LED flashes → **UP/ENTER** → NUMBER LED lights → enter the note number (0–127) with footswitches 1–10/0 as digits or with EXP A → **UP/ENTER** to confirm.
5. If EXP A/B are enabled here: briefly press 8 → UP/ENTER → controller number → confirm → MIN → confirm → MAX → confirm; same for 9.
6. Hold **DOWN** > 2.5 s to store and exit ("Any confirmed entries will be stored with the currently selected PRESET").
7. Repeat for the same switch position in every bank you use.

### 4.2 SysEx dump edit (fcbtool or fcb1010.py)
Procedure: dump the pedal (global setup → footswitch 6 SYSEX SEND, manual p.15; or fcbtool "Receive SysEx Dump"), convert to CSV, edit the row, convert back, send (global setup → footswitch 7 SYSEX RCV, then transmit).

For preset row `Bank=B, Preset=P` (the shift switch) set:
```
col 2,4,6,8,10  Enabled(PC1..PC5)      = 0
col 12          Enabled(CC1)           = 0
col 15          Enabled(CC2)           = 0
col 18, 19      Enabled(Switch 1/2)    = same as your PC presets (relay jacks)
col 20..27      EXP A / EXP B          = copy from a PC preset (Enabled=1 if they use the pedals)
col 28          Enabled(Note)          = 1
col 29          Value(Note)            = note number, e.g. 127 or any note unused on that channel
```
Line 2, column 28 (`Note` channel) = the dedicated channel (raw byte, likely 0-based).

Raw bytes, if you patch the dump directly: for preset index i = (B−1)·10 + (P−1), the 16 enable bits start at flag index 16·i counted from byte 14 in 7-bit groups (skip every 8th byte); set PC1–5/CC1/CC2 bits to **1** (inverted = disabled), NOTE bit (16th) to **0** (enabled); the note number is the 16th value byte of the preset's 16-byte value block starting at byte 7 (skip every 8th byte). Use `parse_sysex`/`get_raw_sysex` rather than hand-counting; the padding makes manual offsets error-prone.

Tool caveats: fcbtool is Linux-only (`-lasound -lncurses`), so on this Windows host use it inside WSL or use the Python library (`rtmidi`); if you use the Python one, set `note_value` on the parsed presets before `save()`/`get_raw_sysex()` because of the `.note` bug (§2.3). Always start from a dump of *your* pedal.

---

## 5. ReaLearn side

- **Note velocity source** (docs.helgoboss.org/realearn/sources/midi/note-velocity.html): "When note-off messages arrive, the source outputs 0%"; filter by channel and note number. A Note On with velocity 0 is a note-off; ReaLearn's Learn will pick the character up as **Button (momentary)**: "emits a > 0% value when pressing it and optionally a 0% value when releasing it" (source concepts page). Avoid "Toggle-only button" character — the docs say it "emits 100%, no matter what the hardware sends". **[confirmed by docs; the vel-0 → 0 % path is MIDI-spec behaviour and reported by users — verify with Learn]**
- **Shift parameter:** mapping 1: source = that note; glue Absolute mode **Normal** (not Toggle), Button filter **Press & release**, Fire mode "Fire on press (or release if > 0 ms)" (glue-section docs); target = ReaLearn's own parameter (FX parameter value on `<This>` → Parameter 1, or the dedicated compartment-parameter target in newer versions — version-dependent). Result: parameter = 100 % while held, 0 % on release.
- **Shifted mappings:** activation condition **"When modifiers on/off"**, Modifier A = Parameter 1, checkbox on; unshifted duplicates with the checkbox off. "A modifier parameter is considered 'on' when its value exceeds 0" (mapping concepts page). Cockos-forum users describe exactly this (solo → p1, mute buttons conditioned on p1).
- **Your PC switches:** "Specific program change" source "is a trigger-only source, that means it always fires 100%" — no release, so PC presets are one-shots; the hold logic must live entirely in the NOTE switch.
- Expression pedals arrive as CC on the EXP A/B channels (7-bit, running status optional); plain CC (absolute) sources — but see §3.4 #1: they do not move while any footswitch is held on stock firmware.

---

## 6. If stock is not clean enough: firmware routes (prices as displayed at https://shop.fcb1010.eu, Firmware category, 2026-09-04)

| Option | Price | What you get for "hold" | Cost to your PC 0–99 layout |
|---|---|---|---|
| **UnO v1.0.4** (fcb1010.eu) | €26 chip | "Momentary effect": CC value on press, CC value 0 (any value in ≥1.0.3) on release; LED on while held; expression pedals still work while a switch is held; NOTE velocity settable; per-preset "leave unchanged" for pedals/relays; block repeated PCs; disable tap-tempo. **But momentary effects exist only in *stompbox mode*, on the 5 stompbox switches** (UnO guide p.7: "in UnO v.1.0.3 and above momentary toggling is available for the 5 stompbox switches only!"). Stompbox mode is incompatible with Direct Select. | Stompbox mode = 19 banks × 5 presets + 5 global stompboxes (one row); PC4 slot lost per preset. You keep 95 PC presets, not 100, and one row is the stompbox row. |
| **UnO2 + editor** (fcb1010.eu) | €50 chip + Win/Mac editor; **online registration, chip locked to one FCB1010** | "Trigger" = momentary switch with separate command lists for press and release, any MIDI type on any of 16 channels (`TRIGGER_CLICK x = SendMidi … NoteOn 69 127` / `TRIGGER_RELEASE x = …`). Presets can also have `PRESET_RELEASE`. Banks are any mix of presets, effects, triggers. Text-based setup, needs MIDI in+out to the PC for upload/registration. | None — build your 10×10 PC banks plus one trigger per bank. Setup memory is 2 KB; 100 presets × 1 PC fit. |
| **FCB-505** (fcb1010.eu) | €26 chip | Zero programming: every footswitch 1–10 sends CC20–CC29, UP = CC30, DOWN = CC31, **value 127 on press, 0 on release, all on channel 13**; pedals CC14/CC15; correct MIDI merge. | Total — no PCs, no banks; 12 momentary buttons. Only viable if ReaLearn does all the banking (it can, with modifiers/banks). |
| **EurekaPROM 3** (eurekasound.com) | $35 chip; $250 for a pre-loaded FCB1010 | IO mode: each switch/pedal → unique CC, every LED addressable by incoming CC (a real DAW I/O surface); Effects mode: toggle 0/127 or "momentary (127)" — release message not documented; SP mode sends Note On and Note Off (rev 2.0). Programmed on the pedal (hold 7+10 at power-up), no editor. Discontinued EurekaPROM2 page exists; check availability. | IO mode drops the PC layout (like FCB-505); PP mode keeps programmable presets. |
| UnO4Kemper | €26 | Kemper-specific | n/a |

**Cheapest clean route that keeps PC 0–99 and one true hold switch: UnO2 (€50).** UnO (€26) works only if you accept the stompbox-mode bank layout; FCB-505 (€26) works only if you drop PCs entirely. Stock firmware costs nothing and works if you accept §3.4.

### 6.1 Installing any of these chips
Behringer's own "Upgrade Manual" (July 2002, https://www.fcb1010.eu/downloads/Upgrade%20Manual_FCB1010_Rev_A.pdf): remove the 14 bottom screws (EurekaSound's guide counts 16 — count yours), lift the bottom panel (ground wire stays attached), the EPROM sits next to the electrolytic capacitor; pull the hot-melt glue off both short ends with pincers, lift the chip vertically (or lever gently with a small screwdriver/EPROM pliers), seat the new chip with its notch matching the socket notch, do not glue, close up. Hold footswitches 1+6 at power-up to load new factory presets. UnO additionally needs a memory init on first boot: hold **1 + 9** at power-up until the display blanks, then a 9→0 countdown (UnO guide p.1). UnO2 shows `-lic` until registered online through UnO2 ControlCenter with the code shipped with the chip (UnO2 manual §4.2). ESD precautions apply. No soldering.

---

## 7. MIDI channel handling summary
- Eight message slots per preset (5 PC, 2 CC, 1 Note) plus 2 pedals; each of the ten slots has **one global channel** (manual table 2.1; UnO guide p.6; UnO2 manual p.3 "each of these 8 messages share the same MIDI channel for all presets"). PC1 could be ch 1 and PC2 ch 2, but *every* preset's PC1 is on ch 1.
- Therefore the cleanest filter for ReaLearn is channel: put NOTE on its own channel and the PCs on another; ReaLearn's "Specific program change" source can then be restricted to the PC channel and the Note source to the NOTE channel.
- Running Status (global) affects only the expression-pedal CC streams per the UnO guide; the comparison PDF says the stock setting "does not work" — leave it off.
- MIDI merge on stock is buggy (hanging notes, "88" at power-up); UnO/UnO2/FCB-505 fix it.

---

## 8. Sources
Local:
- `J:\Portable Workstation\DAW\Utility\fcbtool\src\fcb.h`, `fcb.c`, `ui_ncurses.c`, `docs\fcb1010_dump_format.txt`, `README.md`
- `J:\Portable Workstation\DAW\Utility\fcb1010\fcb1010.py`, `README.md`, `FCB1010.csv`
- Downloaded and text-extracted to the scratchpad: `comparison.txt` (fcb1010.eu Behringer-vs-UnO comparison PDF), `uno_guide.txt` (UnO v1.0.4 User Guide), `uno2_manual.txt` (UnO2 manual, 56 pp.), `cc_manual.txt` (FCB/UnO ControlCenter manual), `fcb505.txt`, `upgrade_manual.txt` (Behringer EPROM upgrade manual).

Web:
- Behringer FCB1010 User Manual via ManualsLib: pages 9–17 of https://www.manualslib.com/manual/1296932/Behringer-Fcb1010.html (p.10 functions/config tables, p.11–13 preset programming and NOTE programming, p.14–15 tap-tempo and SysEx, p.17 MIDI data format, velocity 64). The Behringer CDN PDF https://cdn.mediavalet.com/aunsw/musictribe/0r20680VUk-CGwyX3csF2Q/EIzAkiHQzUiTTW26OjSvhA/Original/FCB1010_P0089_M_EN.pdf returned HTTP 500 during this session.
- UnO comparison: https://www.fcb1010.eu/downloads/comparison%20Behringer%20Uno.pdf
- UnO v1.0.4 User Guide: https://www.fcb1010.eu/downloads/FCB_UnO_v1_0_4_UserGuide.pdf
- UnO feature page: https://www.fcb1010.eu/uno.html ; UnO2: https://www.fcb1010.eu/uno2.html ; UnO2 manual: https://www.fcb1010.eu/downloads/UnO2_Usermanual.pdf
- FCB/UnO ControlCenter manual (stock-firmware chapter incl. NoteOn/NoteOff-on-release, message order, velocity 100): https://www.fcb1010.uno/downloads/FCB_UnO_ControlCenter_manual.pdf
- FCB-505 firmware sheet: https://www.fcb1010.eu/downloads/FCB-505.pdf
- Behringer EPROM upgrade manual: https://www.fcb1010.eu/downloads/Upgrade%20Manual_FCB1010_Rev_A.pdf
- Shop prices (rendered in browser 2026-09-04): https://shop.fcb1010.eu (Firmware: UnO €26, UnO4Kemper €26, FCB-505 €26, UnO2+editor €50; Hardware: Wino2 €49, TinyBox €179)
- UK reseller (shop not yet open): https://fcb1010.uk/
- EurekaPROM: https://www.eurekasound.com/eurekaprom , https://www.eurekasound.com/eurekaprom/io , https://www.eurekasound.com/eurekaprom/pp , https://www.eurekasound.com/eurekaprom/setup
- Forum corroboration: https://www.kvraudio.com/forum/viewtopic.php?t=234296 (note-on held until release), https://forum.loopypro.com/discussion/12983/question-for-behringer-fcb1010-users and https://forum.loopypro.com/discussion/37051/behringer-fcb1010-need-some-user-info-please (CC toggle trick, single LED), https://en.wikibooks.org/wiki/Behringer_FCB1010_MIDI_Pedal (LED = last pedal pressed), https://gearspace.com/board/audio-student-engineering-production-question-zone/1227392-fcb1010-toggle-momentary.html (search snippet only; page returned 500/403).
- ReaLearn: https://docs.helgoboss.org/realearn/sources/midi/note-velocity.html , https://docs.helgoboss.org/realearn/further-concepts/source.html , https://docs.helgoboss.org/realearn/further-concepts/mapping.html (conditional activation), https://docs.helgoboss.org/realearn/user-interface/mapping-panel/glue-section.html , https://docs.helgoboss.org/realearn/sources/midi/specific-program-change.html , https://forum.cockos.com/archive/index.php/t-178015-p-6.html
- Unreachable this session (403/500/refused): Fractal Audio forum threads, Ableton forum thread, voes.be UnO FAQ, mountainutilities.eu FAQ, Reverb/eBay/Amazon listings.

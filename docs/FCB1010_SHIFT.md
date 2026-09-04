# FCB1010 foot switch as a true hold "shift" for the keyboard

The Oxygen Pro 61 cannot give you a hold modifier (its firmware sends nothing for a second button while one is
held), so the Back button is a latch. A Behringer FCB1010 foot switch can be a **real hold**: press = shift on,
release = shift off, while both hands stay on the keyboard.

## How it works

```
FCB1010 switch  --Note On / Note Off (ch 16)-->  MIDI interface  -->  ReaLearn unit "fcb1010-shift"
                                                                          |  SendMidi -> InputDevice "MIDIIN3 (Oxygen Pro 61)"
                                                                          v  CC 105 ch 14, 127 while held / 0 on release
                                                   Oxygen unit: external hold modifier "fcb_shift" -> combos while held
                                                   Exquis unit: the same CC is its shift as well
```

Stock firmware V2.5 has exactly one message type that fires on press **and** release: the preset's **NOTE**
(Note On on press, Note On velocity 0 on release). Program Changes and CCs fire on press only. So the shift
switch is a preset with PC1-5, CNT1 and CNT2 disabled and NOTE enabled, on its own MIDI channel.

## Program the pedal (front panel, stock firmware)

Global NOTE channel (once):

1. Hold **DOWN** while powering on until the display shows the global setup. Leave DIRECT SELECT off.
2. Press **UP/ENTER** to reach the MIDI-function page. Press footswitch **10/0** (NOTE), enter **16** with the
   footswitches, confirm with **UP/ENTER**. Hold **DOWN** about 2.5 s to leave.

The shift preset (repeat for the same switch position in every bank you use):

1. Select the bank and press the switch that will be shift, e.g. switch **10/0**.
2. Hold **DOWN** more than 2.5 s to enter preset programming (SWITCH 1/2 LEDs flash). Set the two relay
   switches like your other presets, confirm with **UP/ENTER**.
3. Each footswitch LED now shows whether that function is enabled. **Hold** a switch about 1.5 s to toggle it:
   LEDs 1-7 **off** (PRG CHG 1-5, CNT 1, CNT 2), LEDs 8 and 9 the same as your other presets (expression
   pedals: a preset that has them off switches the pedals off until the next preset), LED **10/0 on** (NOTE).
4. Briefly press **10/0**, then **UP/ENTER**, enter the note number **60**, confirm with **UP/ENTER**.
5. Hold **DOWN** more than 2.5 s to store.

Known limits of the stock firmware while a switch is held: the expression pedals do not move, the LED jumps to
the shift preset, and CNT 1 must stay disabled in that preset or a double tap sends a tap-tempo CC. If you
want the pedals live while holding, the UnO2 firmware (fcb1010.eu) does press/release for any message.

Alternatively edit a SysEx dump with `Utility/fcbtool` or `Utility/fcb1010`: in the CSV row of the preset set
columns 2, 4, 6, 8, 10 (PC enables), 12 and 15 (CC enables) to 0, column 28 (Note enabled) to 1, column 29
(note number) to 60, and line 2 column 28 (Note channel) to channel 16. Always start from a dump of your own
pedal.

## REAPER side

- `Helgoboss/ReaLearn/controllers.json` gets a third managed controller: input = the MIDI interface the FCB1010
  is plugged into (here `Steinberg UR22mkII -1`), no output, preset `fcb1010/shift`. The first-time setup
  script adds it when it finds a device whose name contains the `FCB_INPUT_MATCH` pattern set at its top.
- `Data/helgoboss/realearn/presets/main/fcb1010/shift.preset.luau` holds the switch definition (`SOURCE`: note
  60 on channel 16 by default) and the two injection targets (Oxygen `MIDIIN3`, Exquis).
- In the Oxygen editor, **Modifiers...** > **Add external hold modifier** (name "FCB shift", CC 105, channel 14),
  then pick the "FCB shift (hold)" layer and assign what each button does while the foot is down. Apply.

The pad indicator (violet/rose checkerboard) follows the foot: on while held, gone on release.

"""Put the M-Audio Oxygen Pro 61's DAW-mode button LEDs under software control.

The keyboard's fader-button LEDs ignore Mackie/HUI LED messages until it receives
M-Audio's private sysex (taken from Ableton Live's bundled Oxygen_Pro remote script):
    F0 00 01 05 7F 00 00 6B 00 01 <v> F7   LED control  (1 = enable, 0 = off)
    F0 00 01 05 7F 00 00 6C 00 01 <v> F7   LED mode     (3 = software, 0 = firmware)
After this, REAPER's stock Mackie Control surface (output = MIDIOUT3) drives
rec/select/mute/solo LEDs with ordinary MCU note-ons. Verified 2026-09-03.

Usage:  python oxygen_led_unlock.py          # unlock (software LEDs)
        python oxygen_led_unlock.py --restore  # hand LEDs back to firmware
Requires python-rtmidi. Works while REAPER holds the port because Windows MIDI
Services makes ports multi-client on this machine.
"""
import sys, time
try:
    import rtmidi
except ImportError:
    sys.exit("python-rtmidi missing: pip install python-rtmidi")
HDR = [0xF0, 0x00, 0x01, 0x05, 0x7F, 0x00, 0x00]
restore = "--restore" in sys.argv
mo = rtmidi.MidiOut()
ports = [i for i, p in enumerate(mo.get_ports()) if "MIDIOUT3" in p and "Oxygen Pro" in p]
if not ports:
    sys.exit("MIDIOUT3 (Oxygen Pro 61) not found - keyboard connected?")
mo.open_port(ports[0])
if restore:
    mo.send_message(HDR + [0x6C, 0x00, 0x01, 0, 0xF7]); time.sleep(0.02)
    mo.send_message(HDR + [0x6B, 0x00, 0x01, 0, 0xF7]); time.sleep(0.02)
    mo.send_message(HDR + [0x6D, 0x00, 0x01, 0, 0xF7])   # firmware mode = normal DAW/Preset presets
    print("Oxygen Pro back to firmware control (normal DAW presets, firmware LEDs)")
else:
    mo.send_message(HDR + [0x6D, 0x00, 0x01, 2, 0xF7]); time.sleep(0.15)   # firmware mode = Live (everything on port 3)
    mo.send_message(HDR + [0x6B, 0x00, 0x01, 1, 0xF7]); time.sleep(0.02)
    mo.send_message(HDR + [0x6C, 0x00, 0x01, 3, 0xF7])
    print("Oxygen Pro in Live mode with software-controlled LEDs (ReaLearn drives them)")
mo.close_port()

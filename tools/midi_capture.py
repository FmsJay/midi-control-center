"""Record everything the Oxygen Pro 61 sends on its two useful USB ports.

Usage:  python midi_capture.py [seconds] [output.txt]      (defaults: 120 s, midi_capture.txt)

Requires python-rtmidi (pip install python-rtmidi). Opens "Oxygen Pro 61" (port 1: keys, aftertouch,
Preset-mode pads) and "MIDIIN3 (Oxygen Pro 61)" (port 3: every Live-mode control) at the same time.
Windows MIDI Services lets REAPER keep the ports open while this runs; on older Windows MIDI stacks
close REAPER first. Each line: seconds since start, port name, hex bytes. Clock ticks (F8) are kept,
filter them with  grep -v F8  if you do not need them.
"""
import sys, time
import rtmidi

seconds = float(sys.argv[1]) if len(sys.argv) > 1 else 120.0
out_path = sys.argv[2] if len(sys.argv) > 2 else "midi_capture.txt"

names = rtmidi.MidiIn().get_ports()
ins = []
for tag in ("Oxygen Pro 61", "MIDIIN3"):
    matches = [k for k, p in enumerate(names) if p.startswith(tag)]
    if not matches:
        print("port not found:", tag, "-- available:", names)
        continue
    m = rtmidi.MidiIn()
    m.open_port(matches[0])
    m.ignore_types(sysex=False, timing=False)
    ins.append((names[matches[0]], m))
if not ins:
    sys.exit(1)

print("recording", [n for n, _ in ins], "for", seconds, "s ->", out_path)
with open(out_path, "w") as out:
    t0 = time.time()
    while time.time() - t0 < seconds:
        got = False
        for name, m in ins:
            e = m.get_message()
            if e:
                out.write("%7.2f  %-28s %s\n" % (time.time() - t0, name, " ".join("%02X" % b for b in e[0])))
                out.flush()
                got = True
        if not got:
            time.sleep(0.004)
print("done")

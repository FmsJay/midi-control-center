"""Keep the Oxygen Pro 61's LEDs under software control across power cycles.

The keyboard forgets the M-Audio "LED mode = software" unlock whenever it is switched off.
This watcher runs alongside REAPER and, whenever the keyboard's port 3 appears (power-on or
re-plug), it:
  1. waits for the device to settle,
  2. re-sends the two unlock sysex messages (same as oxygen_led_unlock.py),
  3. asks REAPER to run "Helgobox/ReaLearn: Send feedback for all instances" through the
     web interface, so every LED and pad repaints from REAPER's actual state.

It exits by itself once REAPER's web interface has been unreachable for a while, so a
REAPER restart never leaves two watchers running. Launched from Scripts/__startup.lua.

Requires python-rtmidi. Works while REAPER holds the port thanks to Windows MIDI Services.
"""
import sys, time, urllib.request

try:
    import rtmidi
except ImportError:
    sys.exit("python-rtmidi missing: pip install python-rtmidi")

REAPER_WEB = "http://127.0.0.1:8080"
RESYNC_ACTION = "_REALEARN_SEND_ALL_FEEDBACK"   # Helgobox/ReaLearn: Send feedback for all instances
PORT_TAG = ("MIDIOUT3", "Oxygen Pro")
HDR = [0xF0, 0x00, 0x01, 0x05, 0x7F, 0x00, 0x00]
POLL_SEC = 2.0
REAPER_GONE_SEC = 45


def find_port():
    mo = rtmidi.MidiOut()
    for i, name in enumerate(mo.get_ports()):
        if all(t in name for t in PORT_TAG):
            return i
    return None


def unlock():
    mo = rtmidi.MidiOut()
    idx = find_port()
    if idx is None:
        return False
    mo.open_port(idx)
    mo.send_message(HDR + [0x6D, 0x00, 0x01, 2, 0xF7]); time.sleep(0.15)   # firmware mode = Live (everything reports on port 3)
    mo.send_message(HDR + [0x6B, 0x00, 0x01, 1, 0xF7]); time.sleep(0.05)   # LED control enable
    mo.send_message(HDR + [0x6C, 0x00, 0x01, 3, 0xF7]); time.sleep(0.05)   # LED mode = software
    mo.close_port()
    return True


def reaper_alive():
    try:
        urllib.request.urlopen(REAPER_WEB + "/_/TRANSPORT", timeout=2).read()
        return True
    except Exception:
        return False


def resync():
    try:
        urllib.request.urlopen(REAPER_WEB + "/_/" + RESYNC_ACTION, timeout=3).read()
    except Exception:
        pass


def main():
    present = find_port() is not None
    if present:
        unlock(); time.sleep(0.5); resync()
    last_alive = time.time()
    while True:
        time.sleep(POLL_SEC)
        now_present = find_port() is not None
        if now_present and not present:
            time.sleep(1.5)           # let the keyboard finish booting
            if unlock():
                time.sleep(0.5); resync()
        present = now_present
        if reaper_alive():
            last_alive = time.time()
        elif time.time() - last_alive > REAPER_GONE_SEC:
            break                     # REAPER is gone; a fresh watcher starts with the next REAPER


if __name__ == "__main__":
    main()

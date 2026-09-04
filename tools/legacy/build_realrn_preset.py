"""Generate the Oxygen Pro 61 User DAW preset "REALRN" from the factory Reaper preset file.

File format (decoded 2026-09-03 with anchor edits in Preset Editor 1.0.2): a flat list of
25-byte records  19 00 00 00 | 00 00 00 00 | id u32 | 0d 00 00 00 | 01 00 00 00 | 0e 00 00 00 | value u8.
The DAW-mode block starts at id 3881 (name at byte 97044, 7 chars).
  faders   : 3881 + bank*45 + fader*5     -> [chan, mode, cc, min, max]        mode 0 CC, 1 Mackie, 2 Mackie/HUI
  buttons  : row_base + (bank*8+btn)*30   -> [?, chan, mode, cc, press, release, ...]
             row_base: Record 4061, Select 5021, Mute 5981, Solo 6941       mode 0 CC ... 6 Note, 7 Mackie, 8 Mackie/HUI
  knobs    : 7962 + bank*40 + knob*5      -> [chan, mode, cc, min, max]
  pads     : 8122 + (bank*16+pad)*11      -> [chan, col1, col2, mode, cc, press, release, note, vel_on, vel_off, ?]
             mode 0 CC, 1 Note, 2 Same as Preset; colours 0 Off 1 Chartreuse 2 Green 3 Aqua 4 Cyan 5 Azure
             6 Blue 7 Violet 8 Magenta 9 Rose 10 Red 11 Orange 12 Yellow 13 White
  bank <   : 8930 -> [chan, mode, cc, press, release]   mode 0 CC, 1 Program, 2 Mackie, 3 Mackie/HUI
  bank >   : 8938 -> same
  chan     : 0 = Global, 1-16 = channel
Layout: DAW/Utility/oxygen-pro-tools/OXYGEN_PRO_61_MAP.md
"""
import struct, sys, shutil, os

SRC = r"J:/Portable Workstation/DAW/Firmware/Install M-Audio Oxygen Pro 61 FWv2.1.2 - Windows/Reaper.OxygenPro61DawPreset"
DST = r"J:/Portable Workstation/DAW/Firmware/Install M-Audio Oxygen Pro 61 FWv2.1.2 - Windows/REALRN.OxygenPro61DawPreset"
NAME = b"REALRN"

buf = bytearray(open(SRC, "rb").read())
pos = {}
o = 0
while o + 25 <= len(buf):
    if buf[o] == 0x19 and buf[o+12] == 0x0d and buf[o+16] == 1 and buf[o+20] == 0x0e:
        pos[struct.unpack_from("<I", buf, o+8)[0]] = o + 24; o += 25
    else:
        o += 1

def setv(i, val):
    buf[pos[i]] = val & 0x7F if val < 128 else val

def getv(i):
    return buf[pos[i]]

# sanity checks against the factory layout before touching anything
assert getv(3882) == 1 and getv(3883) == 33, "fader 1 not where expected"
assert getv(4063) == 7 and getv(4064) == 49, "record button 1 not where expected"
assert getv(7963) == 1, "knob 1 not where expected"
assert [getv(8122+k) for k in range(4)] == [16, 10, 13, 2], "pad 1 not where expected"
assert getv(8932) == 110 and getv(8940) == 111, "bank buttons not where expected"

def fader(bank, f, chan, mode, cc, mn=0, mx=127):
    b = 3881 + bank*45 + f*5
    for k, val in enumerate([chan, mode, cc, mn, mx]): setv(b+k, val)

def knob(bank, k, chan, mode, cc, mn=0, mx=127):
    b = 7962 + bank*40 + k*5
    for j, val in enumerate([chan, mode, cc, mn, mx]): setv(b+j, val)

ROW = {"record": 4061, "select": 5021, "mute": 5981, "solo": 6941}
def button(row, bank, i, chan, mode, cc, press=127, release=0):
    b = ROW[row] + (bank*8 + i)*30
    for j, val in enumerate([chan, mode, cc, press, release]): setv(b+1+j, val)

def pad(bank, p, chan, col1, col2, mode, cc, press=127, release=0):
    b = 8122 + (bank*16 + p)*11
    for j, val in enumerate([chan, col1, col2, mode, cc, press, release]): setv(b+j, val)

def bankbtn(base, chan, mode, cc, press=127, release=0):
    for j, val in enumerate([chan, mode, cc, press, release]): setv(base+j, val)

CC, MACKIE = 0, 1                       # fader/knob modes
B_CC = 0                                # button/pad CC mode
P_CC = 0
GREEN, AZURE, YELLOW, VIOLET, WHITE, BLUE = 2, 5, 12, 7, 13, 6
ROWS = [("select", 32), ("mute", 40), ("solo", 48), ("record", 56)]

# ---- bank 1: Mackie faders/knobs (factory), CC buttons on channel 1 ----------
for row, base_cc in ROWS:
    for i in range(8):
        button(row, 0, i, 1, B_CC, base_cc + i)
# bank 1 pads stay "Same as Preset" (notes 36-51 on the Preset-mode channel, port 1)

# ---- banks 2-4: everything CC on channels 2/3/4 --------------------------------
PAD_COLOURS = {1: (GREEN, AZURE), 2: (YELLOW, VIOLET), 3: (WHITE, WHITE)}
for bank in (1, 2, 3):
    ch = bank + 1
    for f in range(9):  fader(bank, f, ch, CC, 20 + f)
    for k in range(8):  knob(bank, k, ch, CC, 102 + k)
    for row, base_cc in ROWS:
        for i in range(8): button(row, bank, i, ch, B_CC, base_cc + i)
    c_top, c_bottom = PAD_COLOURS[bank]
    for p in range(16):
        col = c_top if p < 8 else c_bottom
        pad(bank, p, ch, col, col, P_CC, 36 + p)

# ---- bank buttons: CC 14 / 15 on channel 1 ------------------------------------
bankbtn(8930, 1, 0, 14)
bankbtn(8938, 1, 0, 15)

# the editor clears this flag when any pad leaves "Same as Preset"
setv(9017, 0)

# preset name (7 chars max, NUL-padded)
buf[97044:97051] = NAME.ljust(7, b"\x00")

open(DST, "wb").write(buf)
print("wrote", DST, len(buf), "bytes")

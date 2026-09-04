"""Generate Exquis key layouts (.xqilayout files for the Exquis app) for a keyboard used ON ITS SIDE:
encoders on the player's left, buttons and slider on the right.

  python tools/exquis_layouts.py [output folder]

Writes three files (default folder: the Exquis app's own Layouts folder, so they appear in the app):
  1  REAPER Piano (sideways)  - a piano: white keys along the player's rows, black keys raised between them
  2  REAPER Drums 4x4         - 16 pads, notes 36-51, four colour rows
  3  Exquis default           - the factory isomorphic layout (chromatic rows, thirds up-left/up-right)

File format (reverse-engineered from the app's own files): <LAYOUT ...><NOTE_LIST> with exactly 61 <NOTE> entries,
one per key, listed from the bottom-left key, row by row upward, left to right; rows alternate 6 / 5 keys and the
5-key rows sit half a key to the right. Colours are ARGB hex; "0" = unlit. flipXY="1" swaps the expression axes,
which is what a sideways keyboard needs so pitch bend follows a sideways finger.

Geometry used here (upright, bottom row first): row r = 1..11, keys c = 1..6 (odd rows) or 1..5 (even rows, at
x = c + 0.5). Turned counter-clockwise (top edge -> left), the player's horizontal axis is r and the vertical axis is
x. So a horizontal "line" of keys for the player is one x value: the even rows give 5 keys at x = c + 0.5, and the
odd rows give 6 keys at x = c that sit exactly between and around them - a piano's white and black rows.
"""
import os, sys

ROWS = [6, 5, 6, 5, 6, 5, 6, 5, 6, 5, 6]          # bottom row first
WHITE, BLACK, OFF = "ffffffff", "ff3a2a80", "0"
NAT, SHARP, C_COL = "ffffe88b", "ff713a82", "ff40c0ff"


def blank():
    return [[(0, OFF) for _ in range(n)] for n in ROWS]   # grid[r-1][c-1] = (note, colour)


def to_xml(name, grid, isomorphic=0, tl=3, tr=4, flipxy=1, transpose=0):
    lines = ['<?xml version="1.0" encoding="UTF-8"?>', '',
             '<LAYOUT name="%s" isomorphic="%d" topLeftInterval="%d" topRightInterval="%d"' % (name, isomorphic, tl, tr),
             '        twoPath="1" transpose="%d" flipX="0" flipY="0" flipXY="%d">' % (transpose, flipxy),
             '  <NOTE_LIST>']
    for row in grid:
        for note, col in row:
            lines.append('    <NOTE noteNumber="%d" colour="%s"/>' % (note, col))
    lines += ['  </NOTE_LIST>', '</LAYOUT>', '']
    return "\n".join(lines)


def piano():
    """Whites on the even rows (5 per player line), blacks on the odd rows one x higher, ends included."""
    g = blank()
    whites = [0, 2, 4, 5, 7, 9, 11]                       # C D E F G A B
    seq = [48 + 12 * o + w for o in range(4) for w in whites]   # C3 upward
    wi = 0
    for c in range(1, 6):                                  # player lines, bottom to top
        line = []
        for r in (2, 4, 6, 8, 10):                         # even rows = 5 whites left to right
            note = seq[wi]; wi += 1
            g[r - 1][c - 1] = (note, WHITE)
            line.append(note)
        # black spots on the odd rows at x = c + 1: left end, four betweens, right end
        prev_note = seq[wi - 6] if wi >= 6 else None       # last white of the line below
        next_note = seq[wi] if wi < len(seq) else None     # first white of the line above
        pairs = [(prev_note, line[0])] + list(zip(line, line[1:])) + [(line[-1], next_note)]
        for r, (lo, hi) in zip((1, 3, 5, 7, 9, 11), pairs):
            if lo is not None and hi is not None and hi - lo == 2:
                g[r - 1][c] = (lo + 1, BLACK)              # index c = x position c + 1
            elif lo is not None and hi is None:
                g[r - 1][c] = (lo + 1, BLACK)              # F#6 at the very end
    return to_xml("REAPER Piano (sideways)", g)


def drums():
    g = blank()
    cols = ["ffff3030", "ffff9020", "ffffe030", "ff30e040"]
    note = 36
    for c in range(1, 5):                                  # four player lines
        for r in (2, 4, 6, 8):                             # four keys per line
            g[r - 1][c - 1] = (note, cols[c - 1]); note += 1
    return to_xml("REAPER Drums 4x4", g)


def exquis_default():
    """Factory rule: +1 per key along a row, up-left +3, up-right +4; bottom-left = C3 (48)."""
    g = blank()
    start = 48
    for r in range(1, 12):
        n = ROWS[r - 1]
        for c in range(1, n + 1):
            note = start + (c - 1)
            col = C_COL if note % 12 == 0 else (NAT if (note % 12) in (2, 4, 5, 7, 9, 11) else SHARP)
            g[r - 1][c - 1] = (note, col)
        start += 4 if r % 2 == 1 else 3                    # 6-row -> 5-row above is up-right (+4); 5-row -> 6-row is up-left (+3)
    return to_xml("Exquis default", g, isomorphic=1, tl=3, tr=4, flipxy=0)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.expanduser("~"), "Documents", "Intuitive Instruments", "Exquis", "Layouts")
    os.makedirs(out, exist_ok=True)
    for name, text in (("REAPER Piano (sideways)", piano()), ("REAPER Drums 4x4", drums()), ("Exquis default", exquis_default())):
        path = os.path.join(out, name + ".xqilayout")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        assert text.count("<NOTE ") == 61, name
        print("wrote", path)


if __name__ == "__main__":
    main()

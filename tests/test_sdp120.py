"""The SDP-120 section of the model must generate the filter / number-entry unit correctly.

Checks (all offline, via lupa):
  * disabled section -> no preset; enabled default -> the full swallow set, no number echo (no numbers assigned)
  * every filter flag adds exactly its own mappings and nothing else
  * assigning a number turns the channel-1 program change into the SendMidi echo (right CC / channel / device)
  * the two panel triggers produce ReaperAction mappings with the expected sources
  * the validator rejects bad numbers, duplicates and missing FX names
  * sdp120_numbers.execute / handle work against a fake reaper (action + FX paths)

Usage: python tests/test_sdp120.py [path/to/midi_control_center]
"""
import os, sys
import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from test_generator import lua_runtime, req, to_py  # noqa: E402


def gen_preset(L, gen, model):
    text = gen.generate_sdp120(model, L.table(date="test"))
    if text is None:
        return None, None
    preset = to_py(gen.evaluate(text))
    assert preset and "mappings" in preset, "generated SDP-120 preset does not evaluate"
    return text, preset


def by_id(preset):
    return {m["id"]: m for m in preset["mappings"]}


def call(fn, *args):
    """Lua functions return (ok, msg) or a lone ok; normalise to a pair."""
    res = fn(*args)
    if isinstance(res, tuple):
        return res[0], (res[1] if len(res) > 1 else None)
    return res, None


def main():
    L = lua_runtime()
    model_mod = req(L, "model")
    gen = req(L, "generator")

    model = model_mod.default()
    assert to_py(model["sdp120"])["enabled"] is False
    assert gen.generate_sdp120(model, L.table()) is None, "disabled section must not generate"

    model["sdp120"]["enabled"] = True
    assert not to_py(model_mod.validate(model)), to_py(model_mod.validate(model))
    text, preset = gen_preset(L, gen, model)
    ids = by_id(preset)
    # default flags: keepalive, gs, 128 ch10 notes, 12 part channels x (1 PC + 128 notes), panel noise 12x10 + 1, tone bank x2 + tone pc ch2 (dup of part-pc-1, skipped) + tone pc ch1
    expected = 1 + 1 + 128 + 12 * 129 + 12 * 10 + 1 + 2 + 1
    assert len(preset["mappings"]) == expected, (len(preset["mappings"]), expected)
    assert ids["keepalive"]["source"]["pattern"] == "F0 33 00 F7"
    assert ids["tone-pc-ch1"]["target"]["kind"] == "Dummy", "no numbers assigned: program change must be swallowed, not echoed"
    assert "tone-number-echo" not in ids
    for ch in (0, 5, 15):   # keys, dual, split channels never get note swallows
        assert not any(m["source"].get("channel") == ch and m["source"]["kind"] == "MidiNoteVelocity" for m in preset["mappings"])
    assert "pedal-dupe-5-64" not in ids

    # each flag alone
    def only(flag):
        m = model_mod.default()
        m["sdp120"]["enabled"] = True
        for f in ("keepalive", "metronome", "rhythm", "gs_sysex", "panel_noise", "tone_changes", "pedal_dupes"):
            m["sdp120"]["filter"][f] = (f == flag)
        return gen_preset(L, gen, m)[1]
    assert len(only("keepalive")["mappings"]) == 1
    assert len(only("gs_sysex")["mappings"]) == 1
    p = only("metronome")["mappings"]
    assert sorted(m["source"]["key_number"] for m in p) == [75, 76]
    assert len(only("rhythm")["mappings"]) == 126 + 12 * 129
    assert len(only("panel_noise")["mappings"]) == 121
    assert len(only("pedal_dupes")["mappings"]) == 6
    t = by_id(only("tone_changes"))
    assert set(t) == {"tone-bank-ch1", "tone-bank-ch2", "part-pc-1", "tone-pc-ch1"}

    # numbers -> echo
    model["sdp120"]["numbers"] = L.table(L.table(number=5, kind="fx", fx="ReaEQ", track="selected"))
    model["sdp120"]["input_device"] = 10
    assert not to_py(model_mod.validate(model))
    text, preset = gen_preset(L, gen, model)
    ids = by_id(preset)
    echo = ids["tone-number-echo"]
    assert "tone-pc-ch1" not in ids
    assert echo["source"] == {"kind": "MidiProgramChangeNumber", "channel": 0}
    assert echo["target"]["kind"] == "SendMidi"
    assert echo["target"]["message"] == "BD 14 [0gfe dcba]", echo["target"]["message"]
    assert echo["target"]["destination"] == {"kind": "InputDevice", "device_id": 10}

    # triggers
    model["sdp120"]["triggers"] = L.table(
        split_voice=L.table(kind="action", command="_SWS_ABOUT"),
        dual_voice=L.table(kind="action", command=40001),
    )
    assert not to_py(model_mod.validate(model))
    text, preset = gen_preset(L, gen, model)
    ids = by_id(preset)
    assert "trigger-sustain-button" not in ids, "the SUSTAIN button must never be mapped (it latches the piano's own sustain)"
    assert ids["trigger-split-voice"]["source"] == {"kind": "MidiProgramChangeNumber", "channel": 15}
    assert ids["trigger-split-voice"]["target"]["command"] == "_SWS_ABOUT"
    assert ids["trigger-split-voice"]["glue"] == {"target_interval": [1, 1]}
    assert ids["trigger-dual-voice"]["source"] == {"kind": "MidiProgramChangeNumber", "channel": 5}
    assert ids["trigger-dual-voice"]["target"] == {"kind": "ReaperAction", "command": 40001, "invocation": "Trigger"}
    assert text.startswith("--- name: Strich SDP-120")

    # validator
    bad = model_mod.default()
    bad["sdp120"]["enabled"] = True
    bad["sdp120"]["numbers"] = L.table(
        L.table(number=0, kind="action", command=1),
        L.table(number=3, kind="fx"),
        L.table(number=3, kind="none"),
        L.table(number=200, kind="none"),
        L.table(number=7, kind="bogus"),
        L.table(number=8, kind="action", command="not a command"),
    )
    errs = to_py(model_mod.validate(bad))
    joined = "\n".join(errs)
    for needle in ("number must be 1-128", "fx name required", "assigned twice", "unknown kind 'bogus'", "_NAMED command"):
        assert needle in joined, (needle, errs)

    # migration
    old = model_mod.default()
    old["sdp120"] = None
    model_mod.sdp120_migrate(old)
    assert to_py(old["sdp120"])["input_name"] == "General MIDI"

    # watcher module against a fake reaper
    L2 = lua_runtime()
    L2.execute("""
        calls = {}
        reaper = {
            ShowConsoleMsg = function(s) calls[#calls+1] = {"log", s} end,
            GetExtState = function() return "g1" end,
            NamedCommandLookup = function(s) return s == "_KNOWN" and 777 or 0 end,
            Main_OnCommand = function(id) calls[#calls+1] = {"cmd", id} end,
            CountTracks = function() return 2 end,
            GetTrack = function(_, i) return "track" .. i end,
            GetSelectedTrack = function() return "selected" end,
            InsertTrackAtIndex = function(i) calls[#calls+1] = {"insert", i} end,
            SetOnlyTrackSelected = function(t) calls[#calls+1] = {"select", t} end,
            Undo_BeginBlock = function() end, Undo_EndBlock = function() end,
            TrackFX_AddByName = function(tr, name, rec, inst) calls[#calls+1] = {"fx", tr, name, inst}; return name == "Missing" and -1 or 3 end,
            TrackFX_Show = function(tr, idx, flag) calls[#calls+1] = {"show", tr, idx, flag} end,
        }
    """)
    S = req(L2, "sdp120_numbers")
    ok, msg = call(S.execute,L2.table(kind="action", command=40001))
    assert ok and to_py(L2.eval("calls[#calls]")) == ["cmd", 40001]
    ok, msg = call(S.execute,L2.table(kind="action", command="_KNOWN"))
    assert ok and to_py(L2.eval("calls[#calls]")) == ["cmd", 777]
    ok, msg = call(S.execute,L2.table(kind="action", command="_UNKNOWN"))
    assert not ok
    ok, msg = call(S.execute,L2.table(kind="fx", fx="ReaEQ", track="selected"))
    assert ok, msg
    c = to_py(L2.eval("calls"))
    assert ["fx", "selected", "ReaEQ", -1] in c and ["show", "selected", 3, 3] in c
    ok, msg = call(S.execute,L2.table(kind="fx", fx="Missing", track="new"))
    assert not ok and "not found" in msg
    c = to_py(L2.eval("calls"))
    assert ["insert", 2] in c
    ok, msg = call(S.execute,L2.table(kind="fx", fx="ReaComp", track="first", reuse=True, show=False))
    assert ok
    assert ["fx", "track0", "ReaComp", 1] in to_py(L2.eval("calls"))
    # handle(): needs a loaded cfg; fake it
    S.cfg = L2.table(); S.status = 0xBD; S.cc = 20
    S.by_number = L2.table()
    S.by_number[5] = L2.table(kind="action", command=40001)
    assert S.handle(0xBD, 20, 4) is True          # value 4 -> number 5
    assert to_py(L2.eval("calls[#calls - 1]")) == ["cmd", 40001]   # the last entry is the console log line
    assert S.handle(0xBD, 20, 9) is True           # nothing assigned: still consumed as an echo
    assert S.handle(0xB0, 20, 4) is False          # wrong channel
    assert S.handle(0xBD, 21, 4) is False          # wrong CC
    print("test_sdp120: OK")


if __name__ == "__main__":
    main()

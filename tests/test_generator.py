"""Offline tests for the MIDI Control Center model + generator (needs `pip install lupa`).

Usage:  python tests/test_generator.py [path/to/midi_control_center] [path/to/reference preset] [--update-golden]

1. The default model must generate a preset that BEHAVES exactly like the reference preset
   (tests/golden/live.preset.golden.luau, a frozen snapshot; the original hand-written preset was the first reference):
   same set of (source, glue, target, effective activation, enabled flags) after expanding group conditions.
   Pass --update-golden after an intentional change to the shipped layout.
2. The generated text must compile and return parameters/groups/mappings with unique ids.
3. A modified model must produce the expected extra mappings; validation must catch broken models.
"""
import json, os, sys
import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
UPDATE_GOLDEN = "--update-golden" in sys.argv
EDITOR_DIR = ARGS[0] if len(ARGS) > 0 else os.path.join(HERE, "..", "reaper", "Scripts", "MIDI Control Center", "midi_control_center")
GOLDEN = os.path.join(HERE, "golden", "live.preset.golden.luau")
REFERENCE = ARGS[1] if len(ARGS) > 1 else GOLDEN
EDITOR_DIR = os.path.abspath(EDITOR_DIR).replace("\\", "/")


def lua_runtime():
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute('package.path = "%s/?.lua;" .. package.path' % EDITOR_DIR)
    return L


def req(L, name):
    r = L.require(name)
    return r[0] if isinstance(r, tuple) else r


def to_py(v):
    """lupa table -> python (dict or list)."""
    if lupa.lua_type(v) == "table":
        keys = list(v.keys())
        if keys and all(isinstance(k, (int, float)) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [to_py(v[k]) for k in sorted(keys)]
        return {str(k): to_py(v[k]) for k in keys}
    return v


def load_preset(L, text, name):
    chunk = L.eval('function(t) return load(t, "%s", "t") end' % name)(text)
    if isinstance(chunk, tuple):
        chunk, err = chunk
        if chunk is None:
            raise SystemExit("%s does not compile: %s" % (name, err))
    return to_py(chunk())


def canon(x):
    return json.dumps(x, sort_keys=True, separators=(",", ":"))


def conditions_of(mapping, groups, params):
    """Expand group + mapping activation into a canonical set of atomic conditions.
    Bank conditions on the layout parameter are expanded so that 'no layout condition' == 'all layouts'."""
    conds = []
    g = groups.get(mapping.get("group", "global"))
    for c in (g.get("activation_condition") if g else None, mapping.get("activation_condition")):
        if c:
            conds.append(c)
    atoms = []
    layouts = None
    for c in conds:
        if c["kind"] == "Bank":
            if c["parameter"] == params["layout"]:
                layouts = c["bank_index"]
            else:
                atoms.append("p%d=%d" % (c["parameter"], c["bank_index"]))
        elif c["kind"] == "Modifier":
            for m in c["modifiers"]:
                atoms.append("mod%d=%s" % (m["parameter"], "on" if m["on"] else "off"))
        else:
            atoms.append(canon(c))
    if layouts is None:
        layouts = "all"
    return sorted(atoms), layouts


# state echoes the generator adds beyond the hand-written preset (Mode, knob function, pad-mode presses -> port 1)
STATE_ECHOES = {"B0 39 7F", "B0 3A 7F", "B0 3B 7F", "B0 3C 7F", "B0 3D 7F", "B0 55 7F", "B0 56 7F", "B0 57 7F", "B0 53 7F", "B0 6B 7F", "B0 6C 7F"}


def is_state_echo(m):
    t = m.get("target") or {}
    return t.get("kind") == "SendMidi" and t.get("message") in STATE_ECHOES


def signature(preset, n_layouts):
    groups = {g["id"]: g for g in preset["groups"]}
    params = {p["id"]: p["index"] for p in preset["parameters"]}
    sig = {}
    for m in preset["mappings"]:
        if is_state_echo(m):
            continue
        atoms, layouts = conditions_of(m, groups, params)
        body = {
            "source": m.get("source"), "glue": m.get("glue"), "target": m.get("target"),
            "control": m.get("control_enabled", True), "feedback": m.get("feedback_enabled", True),
            "on_activate": m.get("on_activate"), "atoms": atoms,
        }
        lay_list = list(range(n_layouts)) if layouts == "all" else [layouts]
        for lay in lay_list:
            key = canon(dict(body, layout=lay))
            sig[key] = sig.get(key, 0) + 1
    return sig


def main():
    L = lua_runtime()
    model_mod = req(L, "model")
    gen = req(L, "generator")
    model = model_mod.default()
    errors = to_py(model_mod.validate(model))
    assert not errors, "default model does not validate: %s" % errors
    # the Off-mode local LEDs are a deliberate addition over the hand-written preset: compare with them off,
    # then check separately that they are generated when on
    with_leds = load_preset(L, gen.generate(model, L.table(date="test")), "generated-with-leds")
    local_ids = [m["id"] for m in with_leds["mappings"] if "-local-" in m["id"] or "-led-m0-local-" in m["id"]]
    assert len(local_ids) == 4 * 2 * len(to_py(model["banks"])), "expected 8 Off-mode LED mappings per bank, got %d" % len(local_ids)
    echoes = [m for m in with_leds["mappings"] if is_state_echo(m)]
    assert len(echoes) == 11, "expected 11 state-echo mappings, got %d" % len(echoes)
    if UPDATE_GOLDEN:
        with open(GOLDEN, "w", encoding="utf-8", newline="\n") as f:
            f.write(gen.generate(model, L.table(date="shipped default", author="MIDI Control Center (shipped default)")))
        print("golden updated:", GOLDEN)
    reference_is_golden = os.path.abspath(REFERENCE) == os.path.abspath(GOLDEN)
    if not reference_is_golden:
        model["off_mode_local_leds"] = False     # the hand-written preset predates the Off-mode LEDs
    text = gen.generate(model, L.table(date="test"))
    generated = load_preset(L, text, "generated")
    reference = load_preset(L, open(REFERENCE, encoding="utf-8").read(), "reference")

    # 2. structure
    ids = [m["id"] for m in generated["mappings"]]
    assert len(ids) == len(set(ids)), "duplicate mapping ids in generated preset"
    print("generated: %d mappings, %d groups, %d parameters" % (len(generated["mappings"]), len(generated["groups"]), len(generated["parameters"])))
    print("reference: %d mappings" % len(reference["mappings"]))

    # 1. behaviour equality
    n_layouts = len(to_py(model["layouts"]))
    sg, sr = signature(generated, n_layouts), signature(reference, n_layouts)
    only_gen = [k for k in sg if k not in sr]
    only_ref = [k for k in sr if k not in sg]
    count_diff = [k for k in sg if k in sr and sg[k] != sr[k]]
    if only_gen or only_ref or count_diff:
        print("BEHAVIOUR DIFFERS: %d only in generated, %d only in reference, %d count mismatches" % (len(only_gen), len(only_ref), len(count_diff)))
        for k in only_gen[:8]:
            print("  +", k[:300])
        for k in only_ref[:8]:
            print("  -", k[:300])
        sys.exit(1)
    print("behaviour identical to the reference preset (%d distinct mapping signatures)" % len(sg))

    # 3. a modified model
    m2 = model_mod.copy(model)
    m2["buttons"]["loop"] = L.table(kind="action", command=40073)          # Loop button -> action
    m2["layouts"][1]["pad_modes"][5]["kind"] = "custom"                        # Free -> custom with one pad (layout 1)
    m2["layouts"][1]["pad_modes"][5]["pads"] = L.table()
    m2["layouts"][1]["pad_modes"][5]["pads"][3] = L.table(kind="action", command=40001, colour="cyan")
    assert not to_py(model_mod.validate(m2)), to_py(model_mod.validate(m2))
    g2 = load_preset(L, gen.generate(m2, L.table(date="test")), "modified")
    by_id = {m["id"]: m for m in g2["mappings"]}
    assert by_id["loop"]["target"]["command"] == 40073, by_id["loop"]
    assert by_id["lay0-p4-pad-3"]["target"]["command"] == 40001
    assert "c = 60" in by_id["lay0-p4-paint-3"]["source"]["script"]
    # an external HOLD modifier (foot switch injected as CC 105 on channel 14)
    m3 = model_mod.copy(model)
    m3["modifiers"]["fcb"] = L.table(external=L.table(name="FCB shift", cc=105, channel=13), combos=L.table(play=L.table(kind="action", command=40029)))
    assert not to_py(model_mod.validate(m3)), to_py(model_mod.validate(m3))
    g3 = load_preset(L, gen.generate(m3, L.table(date="test")), "external-modifier")
    by3 = {m["id"]: m for m in g3["mappings"]}
    pidx = [p["index"] for p in g3["parameters"] if p["id"] == "mod_fcb"][0]
    assert by3["modstate-fcb"]["source"]["controller_number"] == 105 and by3["modstate-fcb"]["source"]["channel"] == 13
    assert "glue" not in by3["modstate-fcb"], "hold modifier must not be a toggle"
    assert by3["mod-fcb-play"]["activation_condition"]["modifiers"][0] == {"parameter": pidx, "on": True}
    assert not any(k.startswith("moddrop-fcb") for k in by3), "hold modifiers must not have drop mappings"
    play_conds = by3["play"]["activation_condition"]["modifiers"]
    assert {"parameter": pidx, "on": False} in play_conds, play_conds
    print("external hold modifier OK")
    # validation catches nonsense
    bad = model_mod.copy(model)
    bad["buttons"]["play"] = L.table(kind="action", command=-5)
    bad["banks"][1]["kind"] = "bogus"
    errs = to_py(model_mod.validate(bad))
    assert len(errs) == 2, errs
    # json round trip
    js = req(L, "json")
    rt = to_py(js.decode(js.encode(model, True)))
    assert canon(rt) == canon(to_py(model)), "json round trip changed the model"
    print("modified model, validation and json round trip OK")


if __name__ == "__main__":
    main()

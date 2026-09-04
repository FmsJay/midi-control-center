"""The Exquis section of the model must generate a preset that behaves exactly like the reference Exquis preset
(tests/golden/exquis.preset.golden.luau, originally the hand-written preset verified on hardware 2026-09-04).

Usage: python tests/test_exquis.py [path/to/oxygen_editor] [reference preset] [--update-golden]
"""
import json, os, sys
import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from test_generator import lua_runtime, req, to_py, load_preset, canon  # noqa: E402

ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
UPDATE_GOLDEN = "--update-golden" in sys.argv
GOLDEN = os.path.join(HERE, "golden", "exquis.preset.golden.luau")
REFERENCE = ARGS[1] if len(ARGS) > 1 else GOLDEN


def signature(preset):
    sig = {}
    for m in preset["mappings"]:
        body = {
            "source": m.get("source"), "glue": m.get("glue"), "target": m.get("target"),
            "control": m.get("control_enabled", True), "feedback": m.get("feedback_enabled", True),
            "cond": m.get("activation_condition"), "on_deactivate": m.get("on_deactivate"),
        }
        key = canon(body)
        sig[key] = sig.get(key, 0) + 1
    return sig


def main():
    L = lua_runtime()
    model_mod = req(L, "model")
    gen = req(L, "generator")
    model = model_mod.default()
    model["exquis"]["enabled"] = True
    errors = to_py(model_mod.validate(model))
    assert not errors, errors
    text = gen.generate_exquis(model, L.table(date="test"))
    assert text, "generate_exquis returned nothing although enabled"
    if UPDATE_GOLDEN:
        with open(GOLDEN, "w", encoding="utf-8", newline="\n") as f:
            f.write(gen.generate_exquis(model, L.table(date="shipped default")))
        print("golden updated:", GOLDEN)
    generated = load_preset(L, text, "exquis-generated")
    reference = load_preset(L, open(REFERENCE, encoding="utf-8").read(), "exquis-reference")
    ids = [m["id"] for m in generated["mappings"]]
    assert len(ids) == len(set(ids)), "duplicate ids"
    sg, sr = signature(generated), signature(reference)
    only_gen = [k for k in sg if k not in sr or sg[k] != sr[k]]
    only_ref = [k for k in sr if k not in sg or sg[k] != sr[k]]
    print("generated %d mappings, reference %d" % (len(generated["mappings"]), len(reference["mappings"])))
    if only_gen or only_ref:
        print("BEHAVIOUR DIFFERS: %d only in generated, %d only in reference" % (len(only_gen), len(only_ref)))
        for k in only_gen[:6]:
            print("  +", k[:260])
        for k in only_ref[:6]:
            print("  -", k[:260])
        sys.exit(1)
    print("Exquis behaviour identical to the reference (%d signatures)" % len(sg))
    # disabled section -> no preset
    model["exquis"]["enabled"] = False
    assert gen.generate_exquis(model, L.table(date="test")) is None
    # validation
    bad = model_mod.copy(model)
    bad["exquis"]["encoders"][2]["kind"] = "bogus"
    bad["exquis"]["buttons"]["play"]["colour"] = "pink"
    errs = to_py(model_mod.validate(bad))
    assert len(errs) == 2, errs
    print("Exquis disabled path and validation OK")


if __name__ == "__main__":
    main()

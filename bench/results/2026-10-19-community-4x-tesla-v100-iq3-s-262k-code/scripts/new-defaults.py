"""What 0.1.45 has on by default that 0.1.44.1 did not have (or had off).

For every STRATA_* in src/ of both trees it collects the code around getenv() and classifies it:
  ON  - the behaviour is active when the variable is NOT set: `v == nullptr || atoi(v) != 0`, `? atoi(v) : 1`, `nullptr ? N(>0) :`
  OPT - active only when the variable is set:          `v != nullptr && ...`, `? atoi(v) : 0`
Prints the variables whose classification changed (not ON in 0.1.44.1, ON in 0.1.45) and the list of
new opt-ins. Classification uses the first match in a file: a hint for a manual reading, not a proof.
"""
import re
import pathlib

ON = re.compile(r"(?:== nullptr \|\||nullptr \? [1-9]|\? (std::)?atoi\([a-z]+\) : [1-9])")
OFF = re.compile(r"!= nullptr &&|\? (std::)?atoi\([a-z]+\) : 0")

def scan(tree):
    out = {}
    root = pathlib.Path(tree) / "src"
    for p in list(root.rglob("*.cpp")) + list(root.rglob("*.cu")) + list(root.rglob("*.cuh")) + list(root.rglob("*.hpp")):
        try:
            t = p.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        for m in re.finditer(r'getenv\("(STRATA_[A-Z0-9_]+)"\)', t):
            var = m.group(1)
            frag = " ".join(t[m.start(): m.start() + 260].split())
            kind = "ON" if ON.search(frag) else ("OPT" if OFF.search(frag) else "?")
            out.setdefault(var, []).append((kind, str(p), frag))
    return out

a = scan("Strata-0.1.44.1.bak")
b = scan("Strata")

def cls(entries):
    kinds = [e[0] for e in entries]
    if "ON" in kinds:
        return "ON"
    if "OPT" in kinds:
        return "OPT"
    return "?"

print("### switches that look on-by-default in 0.1.45 and were not in 0.1.44.1")
changed = 0
for var, entries in sorted(b.items()):
    cb, ca = cls(entries), cls(a.get(var, [])) if var in a else "absent"
    if cb == "ON" and ca != "ON":
        changed += 1
        kind, path, frag = next(e for e in entries if e[0] == "ON")
        print(f"{var}  [0.1.44.1: {ca}]")
        print(f"   {path}")
        print(f"   {frag[:200]}")
print(f"   total: {changed}")

print("\n### new in 0.1.45 as opt-in (absent in 0.1.44.1)")
for var, entries in sorted(b.items()):
    if var not in a:
        print(f"{var}  [{cls(entries)}]")

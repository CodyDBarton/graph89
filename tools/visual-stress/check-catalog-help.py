#!/usr/bin/env python3
"""Check complete glyph restoration and unchanged real-ROM Catalog pixels."""
from pathlib import Path
import argparse
import json

p = argparse.ArgumentParser()
p.add_argument("captures", type=Path)
p.add_argument("--original", type=Path, required=True)
a = p.parse_args()
files = sorted(a.captures.glob("*.pgm"))
for path in files:
    assert path.read_bytes() == (a.original / path.name).read_bytes(), path.name
for path in files:
    cells = json.loads(path.with_suffix(".cells.json").read_text())
    for i, c in enumerate(cells):
        if not 0 <= c[2] <= 3:
            continue
        for d in cells[i+1:]:
            if c[:4] != d[:4]:
                continue
            left, top = max(c[0], c[8]), max(c[1], c[9])
            right, bottom = min(c[0]+c[5], c[10]), min(c[1]+c[6], c[11])
            dl, dt = max(d[0], d[8]), max(d[1], d[9])
            dr, db = min(d[0]+d[5], d[10]), min(d[1]+d[6], d[11])
            assert not (left < dr and dl < right and top < db and dt < bottom), path.name
checks = 0
for line in (a.captures / "actions.txt").read_text().splitlines():
    fields = line.split()
    if len(fields) < 3 or fields[2] != "catalog-help-close":
        continue
    start = int(fields[1])
    # Locate the settled screen immediately before the corresponding F1 press.
    actions = (a.captures / "actions.txt").read_text().splitlines()
    index = actions.index(line)
    open_line = next(x for x in reversed(actions[:index]) if x.split()[2] == "catalog-help-open")
    open_start = int(open_line.split()[1])
    before = [f for f in files if int(f.name[:5]) < open_start][-1]
    next_action = next((int(x.split()[1]) for x in actions[index+1:] if len(x.split()) > 2), len(files))
    after = [f for f in files if start <= int(f.name[:5]) < next_action][-1]
    def body_cells(f):
        return sorted(tuple(c) for c in json.loads(f.with_suffix(".cells.json").read_text()) if 0 <= c[2] <= 3 and 26 <= c[1] < 94)
    assert body_cells(before) == body_cells(after), (before.name, after.name)
    assert before.read_bytes()[-16000:][26*160:94*160] == after.read_bytes()[-16000:][26*160:94*160]
    checks += 1
assert checks == 10, checks
print(f"PASS: {checks} Catalog help dismissals restore complete native glyph identities; {len(files)} LCD frames match reference")

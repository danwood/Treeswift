#!/usr/bin/env python3
"""Summarize strategy-matrix-results.tsv: per-strategy build outcomes + scope-leak check.
ponytail: plain tabulation, no deps."""
import csv, os, collections

HERE = os.path.dirname(os.path.abspath(__file__))
TSV = os.path.join(HERE, "strategy-matrix-results.tsv")

rows = []
with open(TSV) as f:
    for r in csv.DictReader(f, delimiter="\t"):
        rows.append(r)

print(f"# Strategy matrix — {len(rows)} cells\n")

# Per-strategy outcomes.
print("## Build outcome by strategy\n")
print("| strategy | cells | build OK | build FAIL | deleted>0 | scope leaks |")
print("|----------|-------|----------|------------|-----------|-------------|")
by = collections.defaultdict(list)
for r in rows: by[r["strategy"]].append(r)
order = ["skipReferenced", "forceRemoveAll", "cascade"]
for strat in order:
    rs = by.get(strat, [])
    if not rs: continue
    ok = sum(1 for r in rs if r["buildOK"] == "OK")
    fail = sum(1 for r in rs if r["buildOK"] == "FAIL")
    deln = sum(1 for r in rs if int(r["deleted"]) > 0)
    leaks = sum(1 for r in rs if int(r["changedFilesOutsideFolder"]) > 0)
    print(f"| {strat} | {len(rs)} | {ok} | {fail} | {deln} | {leaks} |")
print()

# Expectation check.
print("## Expectation check\n")
print("- skipReferenced (opt 1): expect ALL build OK")
print("- cascade (opt 3): expect ALL build OK")
print("- forceRemoveAll (opt 2): build may pass or fail — informational")
print()
unexpected = [r for r in rows if r["strategy"] in ("skipReferenced", "cascade") and r["buildOK"] != "OK"]
leaks = [r for r in rows if int(r["changedFilesOutsideFolder"]) > 0]
nodelete = [r for r in rows if int(r["deleted"]) == 0]
if unexpected:
    print(f"⚠️ {len(unexpected)} UNEXPECTED build FAILs in opt1/opt3:")
    for r in unexpected:
        print(f"   {r['baseline']}/{r['folder']}/{r['strategy']} — {r['buildErrors']} errors")
else:
    print("✅ opt1 (skipReferenced) + opt3 (cascade): every cell built OK.")
if leaks:
    print(f"⚠️ {len(leaks)} cells changed files OUTSIDE the target folder (scope leak):")
    for r in leaks:
        print(f"   {r['baseline']}/{r['folder']}/{r['strategy']} — {r['changedFilesOutsideFolder']} outside")
else:
    print("✅ scope: every removal stayed inside its target folder.")
print()

# forceRemoveAll breakdown (the interesting one).
fra = by.get("forceRemoveAll", [])
if fra:
    okn = sum(1 for r in fra if r["buildOK"] == "OK")
    print(f"## forceRemoveAll (opt 2): {okn}/{len(fra)} built OK; {len(fra)-okn} failed (expected-possible).")
    for r in fra:
        if r["buildOK"] != "OK":
            print(f"   FAIL {r['baseline']}/{r['folder']} — deleted={r['deleted']} errors={r['buildErrors']}")
print()

# Per-baseline matrix (folder × strategy build result).
print("## Per-cell results\n")
print("| baseline | folder | skipReferenced | forceRemoveAll | cascade |")
print("|----------|--------|----------------|----------------|---------|")
cells = collections.defaultdict(dict)
for r in rows:
    cells[(r["baseline"], r["folder"])][r["strategy"]] = (r["buildOK"], r["deleted"])
for (base, folder), d in cells.items():
    def cell(s):
        if s not in d: return "—"
        ok, dele = d[s]
        mark = "✅" if ok == "OK" else "❌"
        return f"{mark} {ok} (del {dele})"
    print(f"| {base} | {folder} | {cell('skipReferenced')} | {cell('forceRemoveAll')} | {cell('cascade')} |")

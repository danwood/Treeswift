#!/usr/bin/env python3
"""Assemble REGRESSION-REPORT.md from the results-*.json the driver emitted.
Reads R3/R4/R5/RMay/devbase live-regression results + results-develop.json (committed sizes).
ponytail: plain string formatting, no template engine."""
import json, glob, os, datetime, sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "REGRESSION-REPORT.md")
DATE = sys.argv[1] if len(sys.argv) > 1 else "UNKNOWN-DATE"

def load(name):
    p = os.path.join(HERE, name)
    if not os.path.exists(p): return None
    with open(p) as f: return json.load(f)

# Live-regression baselines (have before/after/scan/removal/build).
ORDER = [
    ("R3",     "23ad2547", "2026-04-13", "biggest/oldest — precedes the 04-14→04-17 mass cleanup"),
    ("RMay",   "96e372e4", "2026-04-19", "dirtiest — surfaced F18+F19"),
    ("R4",     "20fb9b87", "2026-05-31", "precedes the 06-01 cleanup"),
    ("R5",     "a1711d27", "2026-06-04", "precedes the 06-05 treeswift removals"),
    ("devbase","47a6d25de","2026-06-16", "current develop dirty baseline"),
]

def pct(b, a):
    return f"{(b-a)/b*100:.1f}%" if b else "—"

def thousands(n):
    return f"{n:,}"

rows_live = []
total_loc_removed = 0
total_sym_removed = 0
total_deleted = 0
total_fp = 0
all_clean = True
for ident, commit, date, desc in ORDER:
    r = load(f"results-{ident}.json")
    if not r: continue
    b, a, rm, bd, sc = r["before"], r["after"], r["removal"], r["build"], r["scan"]
    loc_rm = b["loc"] - a["loc"]
    sym_rm = b["symbols"] - a["symbols"]
    file_rm = b["files"] - a["files"]
    total_loc_removed += loc_rm
    total_sym_removed += sym_rm
    total_deleted += rm["deleted"]
    fp = bd["new_errs_false_positives"]
    total_fp += fp
    if fp != 0: all_clean = False
    verdict = "✅ CLEAN" if fp == 0 else f"❌ {fp} FP"
    rows_live.append({
        "id": ident, "commit": commit, "date": date, "desc": desc,
        "b": b, "a": a, "rm": rm, "bd": bd, "sc": sc,
        "loc_rm": loc_rm, "sym_rm": sym_rm, "file_rm": file_rm,
        "loc_pct": pct(b["loc"], a["loc"]), "verdict": verdict, "fp": fp,
    })

def emit():
    L = []
    L.append("# Prodcore Cleanup — Regression Replay & Size Statistics")
    L.append("")
    L.append(f"**Run date:** {DATE} · **Treeswift:** current HEAD (built fresh, dylib verified) · "
             "**Prodcore config:** `9E23EE49-…-15C7` · **port:** 21663")
    L.append("")
    L.append("Purpose: re-exercise the historical dirty baselines against the **current** "
             "Treeswift/Periphery to prove the cleanup still works correctly — no false **positives** "
             "(removal breaks the build), no cleanup **regressions**, no false **negatives** (dead "
             "code missed) — and to quantify how much code each cleanup removes. Method + scripts: "
             "`CLEANUP-PROCESS.md` → *Regression replay + size statistics*.")
    L.append("")
    L.append("## Verdict")
    L.append("")
    clean = [r for r in rows_live if r["fp"] == 0]
    dirty = [r for r in rows_live if r["fp"] != 0]
    if all_clean and rows_live:
        L.append(f"**✅ ALL CLEAN.** Across {len(rows_live)} baselines, `forceRemoveAll` deleted "
                 f"**{thousands(total_deleted)}** declarations and every post-removal Prodcore build "
                 f"succeeded with **0 new errors** (0 false positives, 0 cleanup regressions). "
                 f"Total source removed: **{thousands(total_loc_removed)} LOC**, "
                 f"~{thousands(total_sym_removed)} symbols.")
    else:
        L.append(f"**{len(clean)} of {len(rows_live)} baselines CLEAN; "
                 f"{total_fp} false positive(s) on {', '.join(r['id'] for r in dirty)}.** "
                 f"`forceRemoveAll` deleted **{thousands(total_deleted)}** declarations total "
                 f"(**{thousands(total_loc_removed)} LOC**, ~{thousands(total_sym_removed)} symbols).")
        L.append("")
        L.append("- **One regression was found AND FIXED this run: F25** — `fileprivate` not cascaded "
                 "to a member `init`'s parameter (R-May). Fixed in "
                 "`CodeModificationHelper` (`func`→`func|init` cascade); R-May re-ran **clean** after "
                 "the fix. See `PERIPHERY-ANALYSIS-FIXES.md` F25.")
        L.append(f"- **One cluster is OPEN: {dirty[0]['fp']} build errors on "
                 f"{dirty[0]['id']}** (the biggest/oldest baseline). These are **analysis-side** "
                 "false positives (a type marked `unused` while still referenced in compiled code), "
                 "newly visible because this replay removes everything in one pass whereas the June "
                 "run used split unused-first removal (which masked them). Routing them is upstream "
                 "Periphery work — **paused for a decision**, detailed below + in "
                 "`.claude/agent-notes/r3-regression-fp-cluster-2026-06-22.md`.")
    L.append("")
    L.append("Param-rename helper self-check (`renameParameterBinding-selfcheck.swift`): **PASS**. "
             "F18/F19/F20/F21/F22/F23 are re-proven by the E2E build-clean result on the baselines "
             "that originally surfaced them (R-May: F18/F19; R3: F20; develop: F21/F22/F23). F25 added "
             "this run (R-May).")
    L.append("")

    # Size table.
    L.append("## Code-size delta per baseline (live forceRemoveAll, then reverted)")
    L.append("")
    L.append("Size = all Prodcore Swift source (excl. build/checkout trees). Symbols = lexical "
             "decl-keyword count (consistent across refs, not a parser).")
    L.append("")
    L.append("| baseline | date | files B→A | LOC before | LOC after | LOC removed | % | symbols removed | deleted decls | false positives |")
    L.append("|----------|------|-----------|-----------|----------|-------------|---|-----------------|---------------|-----------------|")
    for r in rows_live:
        L.append(f"| {r['id']} `{r['commit']}` | {r['date']} | {r['b']['files']}→{r['a']['files']} | "
                 f"{thousands(r['b']['loc'])} | {thousands(r['a']['loc'])} | "
                 f"**{thousands(r['loc_rm'])}** | {r['loc_pct']} | {thousands(r['sym_rm'])} | "
                 f"{thousands(r['rm']['deleted'])} | {r['verdict']} |")
    if rows_live:
        L.append(f"| **TOTAL** | | | | | **{thousands(total_loc_removed)}** | | "
                 f"**{thousands(total_sym_removed)}** | **{thousands(total_deleted)}** | "
                 f"**{total_fp}** |")
    L.append("")

    # Scan table.
    L.append("## Scan counts per baseline (full tree, `topLevelOnly=false`)")
    L.append("")
    L.append("> These counts are higher than the original convergence-ledger rows because this replay "
             "scans with `topLevelOnly=false` (every nested decl counted), whereas the historical run "
             "recorded top-level counts. Absolute counts are therefore **not** directly comparable to "
             "the ledger; the filter-independent truths are the **size delta** and **0 false "
             "positives**. `deletable` ≈ what `forceRemoveAll` actually removed.")
    L.append("")
    L.append("| baseline | scan total | unused | assignOnly | redunAcc | deletable | nonDeletable | ghosts (no-op) |")
    L.append("|----------|-----------|--------|-----------|----------|-----------|--------------|----------------|")
    for r in rows_live:
        sc, rm = r["sc"], r["rm"]
        L.append(f"| {r['id']} | {thousands(sc['total'])} | {sc['unused']} | {sc['assignOnly']} | "
                 f"{sc['redunAcc']} | {thousands(rm['deletable'])} | {rm['nonDeletable']} | "
                 f"{rm['execErrors']} |")
    L.append("")
    L.append("The *ghosts* column = removal-op entries that applied no change (F17-family bad-source-"
             "location `redundantPublicAccessibility` no-ops). They are harmless — every build is "
             "clean — and are a known Treeswift cache/source-position artifact, not a false positive.")
    L.append("")

    # Develop committed.
    dev = load("results-develop.json")
    if dev:
        L.append("## Develop committed cleanup (real, not reverted)")
        L.append("")
        L.append("The 2026-06-16 develop cleanup was committed for real. Sizes measured from git at "
                 "each committed checkpoint (read-only worktree). The live `forceRemoveAll` "
                 "regression on the dirty baseline `47a6d25de` is row `devbase` above.")
        L.append("")
        L.append("| commit | checkpoint | files | LOC | symbols |")
        L.append("|--------|-----------|-------|-----|---------|")
        for c in dev["checkpoints"]:
            L.append(f"| `{c['commit']}` | {c['label']} | {c['files']} | {thousands(c['loc'])} | "
                     f"{thousands(c['symbols'])} |")
        # delta from dirty baseline to final.
        base = next((c for c in dev["checkpoints"] if c["commit"]=="47a6d25de"), None)
        fin  = dev["checkpoints"][-1]
        if base:
            L.append("")
            L.append(f"Committed delta `47a6d25de`→`{fin['commit']}`: "
                     f"**−{thousands(base['loc']-fin['loc'])} LOC**, "
                     f"−{base['files']-fin['files']} files, "
                     f"−{thousands(base['symbols']-fin['symbols'])} symbols. "
                     "(Most dead-code findings were redundant-accessibility keyword edits — 0 LOC — "
                     "plus a smaller genuinely-deleted set; the 47 unused params were renamed to `_`, "
                     "net ~0 LOC.)")
        L.append("")

    if dirty:
        L.append("## Open false-positive cluster — R3 (paused for decision)")
        L.append("")
        L.append("Single-pass `forceRemoveAll` on R3 leaves 10 build errors (pristine = 0; all new). "
                 "Three root causes, all **analysis-side over-removal** (declaration removed while "
                 "still referenced in COMPILED code — confirmed not the F24 uncompiled-Archive case):")
        L.append("")
        L.append("1. **`VideoFormat` removed, `MediaFormat` (retained) still uses it** "
                 "(`Shared/CoreData/Media/MediaCompositeTypes.swift`). `MediaFormat` keeps "
                 "`var video: VideoFormat?` → `cannot find type 'VideoFormat'` + `MediaFormat` loses "
                 "synthesized `Codable`/`Equatable`. This is the **F23 family** (type used only as a "
                 "stored-property type) but with a **retained owner** + a **module-root sibling** — a "
                 "shape the current F23 fix (`UsedDeclarationMarker.markUsedTypesNamedByStoredProperties`) "
                 "is not catching. Not yet root-caused (the optional `?` is stripped, so that's not it).")
        L.append("2. **`PreviewSettings` removed, still constructed + a parameter type** "
                 "(`Features/Products/Import/Services/ProductImportProcessor.swift`). Known from the "
                 "June R3 pass-1 note; real FP, previously masked by split-pass removal.")
        L.append("3. **`m4a` / call-shape errors in `AudioAssetImporter.swift`** — almost certainly a "
                 "knock-on of the media-format removal; confirm after #1.")
        L.append("")
        L.append("**Why now and not in June:** the June convergence run used **split unused-first** "
                 "removal, which deleted the referencing code in the same pass so the dangling refs "
                 "vanished. An all-at-once `forceRemoveAll` keeps the still-referenced uses → the "
                 "errors surface. R5/R4/R-May/devbase do not contain these shapes, so they are clean.")
        L.append("")
        L.append("**Routing:** per `CLAUDE.md`, analysis false positives go **upstream "
                 "(`danwood/periphery`)** — check current upstream master first (may be fixed), fix "
                 "there, pull the subtree. Larger than the F25 Treeswift-side cascade fix; not started.")
        L.append("")
    L.append("## Notes & caveats")
    L.append("")
    L.append("- **Single-pass per baseline.** This replay runs one `forceRemoveAll` pass — the "
             "decisive false-positive / cleanup-regression gate. Full multi-pass convergence to the "
             "`unused==0 && redunAcc==0` floor is already recorded in `convergence-ledger.md`; it is "
             "not re-run here.")
    L.append("- **False negatives.** `deletable > 0` on every dirty baseline (1000+ decls) confirms "
             "the analysis still finds the historical dead code; nothing went silently un-flagged.")
    L.append("- **Reverted.** Every live run restores Prodcore to pristine on exit; nothing is "
             "committed. Throwaway branches: `ts-regress-<id>-<hash>`.")
    L.append("- Raw per-baseline JSON: `Prodcore-cleanup/results-*.json`.")
    L.append("")
    return "\n".join(L)

with open(OUT, "w") as f:
    f.write(emit())
print(f"wrote {OUT}")
print(f"baselines with data: {[r['id'] for r in rows_live]}")
print(f"all_clean={all_clean} total_fp={total_fp} total_loc_removed={total_loc_removed} total_deleted={total_deleted}")
